-- Migration 036: Ingestion Health Views + Gap Detection
-- TASK-A1: Build Ingestion Health Views + Gap Detection
--
-- Creates ops.ingestion_gaps view showing gaps in data ingestion
-- Creates ops.ingestion_health summary with status per source

-- =============================================================================
-- View: ops.ingestion_gaps
-- Purpose: Detect and report gaps in data ingestion by source
-- =============================================================================
CREATE OR REPLACE VIEW ops.ingestion_gaps AS
WITH source_config AS (
  -- Define expected frequency for each source (in hours)
  SELECT 'whoop' AS source, 'health' AS domain, 12 AS expected_frequency_hours, true AS daily_expected
  UNION ALL SELECT 'bank_sms', 'finance', 48, false
  UNION ALL SELECT 'healthkit', 'health', 168, false  -- Weekly (manual via iOS app)
  UNION ALL SELECT 'location', 'life', 48, false
  UNION ALL SELECT 'behavioral', 'life', 48, false
  UNION ALL SELECT 'github', 'productivity', 12, false
  UNION ALL SELECT 'receipts', 'finance', 48, false
  UNION ALL SELECT 'finance_summary', 'insights', 36, true
),
-- Generate date series for last 7 days
date_series AS (
  SELECT generate_series(
    CURRENT_DATE - INTERVAL '6 days',
    CURRENT_DATE,
    INTERVAL '1 day'
  )::date AS day
),
-- Aggregate events per day per source
daily_events AS (
  -- WHOOP: One recovery record per day expected
  SELECT
    'whoop' AS source,
    date AS day,
    COUNT(*) AS event_count,
    MAX(created_at) AS last_event_in_day
  FROM health.whoop_recovery
  WHERE date >= CURRENT_DATE - 6
  GROUP BY date

  UNION ALL

  -- Bank SMS: Transactions from SMS
  SELECT
    'bank_sms' AS source,
    date AS day,
    COUNT(*) AS event_count,
    MAX(created_at) AS last_event_in_day
  FROM finance.transactions
  WHERE external_id LIKE 'sms:%'
    AND date >= CURRENT_DATE - 6
  GROUP BY date

  UNION ALL

  -- HealthKit: Weight/health metrics from iOS
  SELECT
    'healthkit' AS source,
    date AS day,
    COUNT(*) AS event_count,
    MAX(created_at) AS last_event_in_day
  FROM health.metrics
  WHERE source = 'healthkit'
    AND date >= CURRENT_DATE - 6
  GROUP BY date

  UNION ALL

  -- Location: HA device tracker events
  SELECT
    'location' AS source,
    created_at::date AS day,
    COUNT(*) AS event_count,
    MAX(created_at) AS last_event_in_day
  FROM life.locations
  WHERE created_at >= NOW() - INTERVAL '7 days'
  GROUP BY created_at::date

  UNION ALL

  -- Behavioral: Sleep/wake/TV events
  SELECT
    'behavioral' AS source,
    created_at::date AS day,
    COUNT(*) AS event_count,
    MAX(created_at) AS last_event_in_day
  FROM life.behavioral_events
  WHERE created_at >= NOW() - INTERVAL '7 days'
  GROUP BY created_at::date

  UNION ALL

  -- GitHub: Activity events
  SELECT
    'github' AS source,
    created_at_github::date AS day,
    COUNT(*) AS event_count,
    MAX(ingested_at) AS last_event_in_day
  FROM raw.github_events
  WHERE created_at_github >= NOW() - INTERVAL '7 days'
  GROUP BY created_at_github::date

  UNION ALL

  -- Receipts: Parsed receipts from Gmail
  SELECT
    'receipts' AS source,
    created_at::date AS day,
    COUNT(*) AS event_count,
    MAX(created_at) AS last_event_in_day
  FROM finance.receipts
  WHERE created_at >= NOW() - INTERVAL '7 days'
  GROUP BY created_at::date

  UNION ALL

  -- Finance Summary: Daily summary generation
  SELECT
    'finance_summary' AS source,
    summary_date AS day,
    COUNT(*) AS event_count,
    MAX(generated_at) AS last_event_in_day
  FROM insights.daily_finance_summary
  WHERE summary_date >= CURRENT_DATE - 6
  GROUP BY summary_date
),
-- Cross-join to detect gaps
full_matrix AS (
  SELECT
    sc.source,
    sc.domain,
    sc.expected_frequency_hours,
    sc.daily_expected,
    ds.day,
    COALESCE(de.event_count, 0) AS event_count,
    de.last_event_in_day
  FROM source_config sc
  CROSS JOIN date_series ds
  LEFT JOIN daily_events de ON sc.source = de.source AND ds.day = de.day
),
-- Identify gaps (days with no events for sources that expect daily data)
gaps_raw AS (
  SELECT
    source,
    domain,
    expected_frequency_hours,
    day,
    event_count,
    -- Calculate gap hours from previous event
    EXTRACT(EPOCH FROM (day::timestamp - LAG(last_event_in_day) OVER (
      PARTITION BY source ORDER BY day
    ))) / 3600 AS gap_hours_from_prev
  FROM full_matrix
  WHERE daily_expected = true OR event_count > 0
)
SELECT
  source,
  domain,
  expected_frequency_hours,
  -- Count gaps in last 7 days (where gap > expected * 1.5)
  COUNT(*) FILTER (WHERE gap_hours_from_prev > expected_frequency_hours * 1.5 AND day <= CURRENT_DATE) AS gap_count_7d,
  -- Maximum gap observed
  ROUND(MAX(gap_hours_from_prev)::numeric, 1) AS max_gap_hours,
  -- Average gap between events
  ROUND(AVG(gap_hours_from_prev)::numeric, 1) AS avg_gap_hours,
  -- Status based on gap severity
  CASE
    WHEN MAX(gap_hours_from_prev) IS NULL THEN 'no_data'
    WHEN MAX(gap_hours_from_prev) > expected_frequency_hours * 3 THEN 'critical'
    WHEN MAX(gap_hours_from_prev) > expected_frequency_hours * 1.5 THEN 'degraded'
    ELSE 'healthy'
  END AS gap_status
FROM gaps_raw
GROUP BY source, domain, expected_frequency_hours
ORDER BY
  CASE WHEN MAX(gap_hours_from_prev) IS NULL THEN 4
       WHEN MAX(gap_hours_from_prev) > expected_frequency_hours * 3 THEN 1
       WHEN MAX(gap_hours_from_prev) > expected_frequency_hours * 1.5 THEN 2
       ELSE 3 END,
  source;

COMMENT ON VIEW ops.ingestion_gaps IS 'Detects and reports gaps in data ingestion by source over last 7 days';

-- =============================================================================
-- View: ops.ingestion_health
-- Purpose: Comprehensive health summary per source combining current status + gap history
-- =============================================================================
CREATE OR REPLACE VIEW ops.ingestion_health AS
WITH current_health AS (
  SELECT
    source,
    domain,
    last_event_at,
    events_24h,
    EXTRACT(EPOCH FROM expected_frequency) / 3600 AS expected_frequency_hours,
    status AS current_status,
    hours_since_last,
    notes
  FROM ops.v_pipeline_health
),
gap_history AS (
  SELECT
    source,
    gap_count_7d,
    max_gap_hours,
    avg_gap_hours,
    gap_status
  FROM ops.ingestion_gaps
)
SELECT
  ch.source,
  ch.domain,
  ch.last_event_at,
  ch.events_24h,
  ch.expected_frequency_hours,
  ch.hours_since_last,
  ch.current_status,
  -- Gap metrics from history
  COALESCE(gh.gap_count_7d, 0) AS gaps_7d,
  gh.max_gap_hours,
  gh.avg_gap_hours,
  -- Overall health: combine current status with gap history
  CASE
    WHEN ch.current_status = 'critical' OR ch.current_status = 'never' THEN 'critical'
    WHEN ch.current_status = 'stale' OR COALESCE(gh.gap_count_7d, 0) >= 3 THEN 'degraded'
    WHEN ch.current_status = 'ok' AND COALESCE(gh.gap_count_7d, 0) = 0 THEN 'healthy'
    WHEN ch.current_status = 'ok' AND COALESCE(gh.gap_count_7d, 0) BETWEEN 1 AND 2 THEN 'acceptable'
    ELSE 'unknown'
  END AS overall_health,
  -- Health score (0-100)
  CASE
    WHEN ch.current_status = 'critical' OR ch.current_status = 'never' THEN 0
    WHEN ch.current_status = 'stale' THEN 25
    WHEN COALESCE(gh.gap_count_7d, 0) >= 3 THEN 50
    WHEN COALESCE(gh.gap_count_7d, 0) BETWEEN 1 AND 2 THEN 75
    ELSE 100
  END AS health_score,
  ch.notes
FROM current_health ch
LEFT JOIN gap_history gh ON ch.source = gh.source
ORDER BY
  CASE ch.current_status
    WHEN 'critical' THEN 1
    WHEN 'never' THEN 2
    WHEN 'stale' THEN 3
    ELSE 4
  END,
  gh.gap_count_7d DESC NULLS LAST,
  ch.source;

COMMENT ON VIEW ops.ingestion_health IS 'Comprehensive health summary per source combining current status + 7-day gap history';

-- =============================================================================
-- View: ops.ingestion_health_summary
-- Purpose: Aggregated summary for dashboard consumption
-- =============================================================================
CREATE OR REPLACE VIEW ops.ingestion_health_summary AS
SELECT
  COUNT(*) AS total_sources,
  COUNT(*) FILTER (WHERE overall_health = 'healthy') AS sources_healthy,
  COUNT(*) FILTER (WHERE overall_health = 'acceptable') AS sources_acceptable,
  COUNT(*) FILTER (WHERE overall_health = 'degraded') AS sources_degraded,
  COUNT(*) FILTER (WHERE overall_health = 'critical') AS sources_critical,
  ROUND(AVG(health_score)::numeric, 0) AS avg_health_score,
  SUM(gaps_7d) AS total_gaps_7d,
  -- Overall system status
  CASE
    WHEN COUNT(*) FILTER (WHERE overall_health = 'critical') > 0 THEN 'critical'
    WHEN COUNT(*) FILTER (WHERE overall_health = 'degraded') > 0 THEN 'degraded'
    WHEN COUNT(*) FILTER (WHERE overall_health = 'acceptable') > 0 THEN 'acceptable'
    ELSE 'healthy'
  END AS system_status,
  NOW() AS generated_at
FROM ops.ingestion_health;

COMMENT ON VIEW ops.ingestion_health_summary IS 'Aggregated ingestion health summary for dashboard';

-- =============================================================================
-- Function: ops.get_ingestion_health_json()
-- Purpose: Returns ingestion health as JSON for API consumption
-- =============================================================================
CREATE OR REPLACE FUNCTION ops.get_ingestion_health_json()
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
  SELECT jsonb_build_object(
    'summary', (SELECT row_to_json(s) FROM ops.ingestion_health_summary s),
    'sources', (
      SELECT jsonb_agg(row_to_json(h) ORDER BY health_score ASC)
      FROM ops.ingestion_health h
    ),
    'gaps', (
      SELECT jsonb_agg(row_to_json(g) ORDER BY gap_count_7d DESC)
      FROM ops.ingestion_gaps g
      WHERE gap_count_7d > 0
    ),
    'generated_at', NOW()
  );
$$;

COMMENT ON FUNCTION ops.get_ingestion_health_json() IS 'Returns ingestion health as JSON for API consumption';
