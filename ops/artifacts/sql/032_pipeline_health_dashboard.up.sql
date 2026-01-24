-- Migration 032: Pipeline Health Dashboard + Alerts
-- Purpose: Unified pipeline health monitoring with alerting
-- Created: 2026-01-24
-- Task: TASK-071

-- ============================================================================
-- 1. Pipeline Alerts Table
-- ============================================================================
CREATE TABLE IF NOT EXISTS ops.pipeline_alerts (
    id SERIAL PRIMARY KEY,
    alert_type VARCHAR(50) NOT NULL,  -- feed_stale, feed_error, anomaly_spike, etc.
    source VARCHAR(50) NOT NULL,       -- whoop, bank_sms, healthkit, etc.
    severity VARCHAR(20) NOT NULL DEFAULT 'warning',  -- info, warning, critical
    message TEXT NOT NULL,
    metadata JSONB,
    acknowledged_at TIMESTAMPTZ,
    acknowledged_by VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_pipeline_alerts_created ON ops.pipeline_alerts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pipeline_alerts_unresolved ON ops.pipeline_alerts(source, alert_type)
    WHERE resolved_at IS NULL;

COMMENT ON TABLE ops.pipeline_alerts IS 'Pipeline health alerts for monitoring';

-- ============================================================================
-- 2. Unified Pipeline Health View
-- ============================================================================
CREATE OR REPLACE VIEW ops.v_pipeline_health AS
WITH feed_sources AS (
    -- WHOOP (via HA → n8n)
    SELECT
        'whoop' AS source,
        'health' AS domain,
        MAX(created_at) AS last_event_at,
        COUNT(*) FILTER (WHERE date >= CURRENT_DATE - 1) AS events_24h,
        '1 hour'::interval AS expected_frequency,
        'HA polls WHOOP every 15 min' AS notes
    FROM health.whoop_recovery

    UNION ALL

    -- Bank SMS (fswatch → importer)
    SELECT
        'bank_sms' AS source,
        'finance' AS domain,
        MAX(created_at) AS last_event_at,
        COUNT(*) FILTER (WHERE date >= CURRENT_DATE - 1) AS events_24h,
        '24 hours'::interval AS expected_frequency,
        'Triggered by fswatch on chat.db' AS notes
    FROM finance.transactions
    WHERE external_id LIKE 'sms:%'

    UNION ALL

    -- HealthKit (iOS app sync)
    SELECT
        'healthkit' AS source,
        'health' AS domain,
        MAX(created_at) AS last_event_at,
        COUNT(*) FILTER (WHERE date >= CURRENT_DATE - 1) AS events_24h,
        '24 hours'::interval AS expected_frequency,
        'iOS app syncs on open' AS notes
    FROM health.metrics
    WHERE source = 'healthkit'

    UNION ALL

    -- Location (HA automations)
    SELECT
        'location' AS source,
        'life' AS domain,
        MAX(created_at) AS last_event_at,
        COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '24 hours') AS events_24h,
        '24 hours'::interval AS expected_frequency,
        'HA device_tracker automations' AS notes
    FROM life.locations

    UNION ALL

    -- Behavioral Events (HA automations)
    SELECT
        'behavioral' AS source,
        'life' AS domain,
        MAX(created_at) AS last_event_at,
        COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '24 hours') AS events_24h,
        '24 hours'::interval AS expected_frequency,
        'HA sleep/wake/TV automations' AS notes
    FROM life.behavioral_events

    UNION ALL

    -- GitHub (n8n cron)
    SELECT
        'github' AS source,
        'productivity' AS domain,
        MAX(ingested_at) AS last_event_at,
        COUNT(*) FILTER (WHERE ingested_at >= NOW() - INTERVAL '24 hours') AS events_24h,
        '6 hours'::interval AS expected_frequency,
        'n8n syncs every 6 hours' AS notes
    FROM raw.github_events

    UNION ALL

    -- Receipts (Gmail → n8n)
    SELECT
        'receipts' AS source,
        'finance' AS domain,
        MAX(created_at) AS last_event_at,
        COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '24 hours') AS events_24h,
        '6 hours'::interval AS expected_frequency,
        'n8n polls Gmail every 6 hours' AS notes
    FROM finance.receipts

    UNION ALL

    -- Daily Finance Summary (generator)
    SELECT
        'finance_summary' AS source,
        'insights' AS domain,
        MAX(generated_at) AS last_event_at,
        COUNT(*) FILTER (WHERE generated_at >= NOW() - INTERVAL '24 hours') AS events_24h,
        '24 hours'::interval AS expected_frequency,
        'Daily summary generator' AS notes
    FROM insights.daily_finance_summary
)
SELECT
    source,
    domain,
    last_event_at,
    events_24h,
    expected_frequency,
    CASE
        WHEN last_event_at IS NULL THEN 'never'
        WHEN last_event_at >= NOW() - expected_frequency THEN 'ok'
        WHEN last_event_at >= NOW() - (expected_frequency * 2) THEN 'stale'
        ELSE 'critical'
    END AS status,
    CASE
        WHEN last_event_at IS NULL THEN NULL
        ELSE EXTRACT(EPOCH FROM (NOW() - last_event_at)) / 3600
    END AS hours_since_last,
    notes
FROM feed_sources
ORDER BY
    CASE
        WHEN last_event_at IS NULL THEN 3
        WHEN last_event_at >= NOW() - expected_frequency THEN 1
        WHEN last_event_at >= NOW() - (expected_frequency * 2) THEN 2
        ELSE 3
    END,
    source;

COMMENT ON VIEW ops.v_pipeline_health IS 'Unified pipeline health status for all data sources';

-- ============================================================================
-- 3. Active Alerts View (unresolved)
-- ============================================================================
CREATE OR REPLACE VIEW ops.v_active_alerts AS
SELECT
    id,
    alert_type,
    source,
    severity,
    message,
    metadata,
    created_at,
    EXTRACT(EPOCH FROM (NOW() - created_at)) / 3600 AS hours_open
FROM ops.pipeline_alerts
WHERE resolved_at IS NULL
ORDER BY
    CASE severity
        WHEN 'critical' THEN 1
        WHEN 'warning' THEN 2
        ELSE 3
    END,
    created_at DESC;

COMMENT ON VIEW ops.v_active_alerts IS 'Currently active (unresolved) pipeline alerts';

-- ============================================================================
-- 4. Health Check Function (creates alerts for stale feeds)
-- ============================================================================
CREATE OR REPLACE FUNCTION ops.check_pipeline_health()
RETURNS TABLE(feed_source TEXT, feed_status TEXT, alert_created BOOLEAN) AS $fn$
DECLARE
    rec RECORD;
    v_alert_created BOOLEAN;
BEGIN
    FOR rec IN
        SELECT p.source, p.domain, p.status, p.last_event_at, p.events_24h, p.expected_frequency, p.hours_since_last
        FROM ops.v_pipeline_health p
        WHERE p.status IN ('stale', 'critical', 'never')
    LOOP
        v_alert_created := FALSE;

        IF NOT EXISTS (
            SELECT 1 FROM ops.pipeline_alerts a
            WHERE a.source = rec.source
              AND a.alert_type = 'feed_' || rec.status
              AND a.resolved_at IS NULL
              AND a.created_at > NOW() - INTERVAL '24 hours'
        ) THEN
            INSERT INTO ops.pipeline_alerts (alert_type, source, severity, message, metadata)
            VALUES (
                'feed_' || rec.status,
                rec.source,
                CASE rec.status WHEN 'critical' THEN 'critical' WHEN 'never' THEN 'critical' ELSE 'warning' END,
                format('%s feed is %s (last: %s)', rec.source, rec.status, COALESCE(rec.last_event_at::text, 'never')),
                jsonb_build_object('domain', rec.domain, 'hours_since', rec.hours_since_last)
            );
            v_alert_created := TRUE;
        END IF;

        feed_source := rec.source;
        feed_status := rec.status;
        alert_created := v_alert_created;
        RETURN NEXT;
    END LOOP;

    -- Auto-resolve alerts for sources that are now OK
    UPDATE ops.pipeline_alerts a
    SET resolved_at = NOW()
    WHERE a.resolved_at IS NULL
      AND a.alert_type LIKE 'feed_%'
      AND EXISTS (SELECT 1 FROM ops.v_pipeline_health p WHERE p.source = a.source AND p.status = 'ok');

    RETURN;
END;
$fn$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ops.check_pipeline_health() IS 'Check all feeds and create alerts for stale/critical sources';

-- ============================================================================
-- 5. Dashboard Summary View
-- ============================================================================
CREATE OR REPLACE VIEW ops.v_dashboard_health_summary AS
SELECT
    (SELECT COUNT(*) FROM ops.v_pipeline_health WHERE status = 'ok') AS feeds_ok,
    (SELECT COUNT(*) FROM ops.v_pipeline_health WHERE status = 'stale') AS feeds_stale,
    (SELECT COUNT(*) FROM ops.v_pipeline_health WHERE status IN ('critical', 'never')) AS feeds_critical,
    (SELECT COUNT(*) FROM ops.v_pipeline_health) AS feeds_total,
    (SELECT COUNT(*) FROM ops.v_active_alerts WHERE severity = 'critical') AS alerts_critical,
    (SELECT COUNT(*) FROM ops.v_active_alerts WHERE severity = 'warning') AS alerts_warning,
    (SELECT COUNT(*) FROM ops.v_active_alerts) AS alerts_total,
    CASE
        WHEN (SELECT COUNT(*) FROM ops.v_pipeline_health WHERE status IN ('critical', 'never')) > 0 THEN 'CRITICAL'
        WHEN (SELECT COUNT(*) FROM ops.v_pipeline_health WHERE status = 'stale') > 2 THEN 'DEGRADED'
        WHEN (SELECT COUNT(*) FROM ops.v_pipeline_health WHERE status = 'stale') > 0 THEN 'WARNING'
        ELSE 'HEALTHY'
    END AS overall_status,
    NOW() AS checked_at;

COMMENT ON VIEW ops.v_dashboard_health_summary IS 'High-level health summary for dashboard';

-- ============================================================================
-- 6. Acknowledge Alert Function
-- ============================================================================
CREATE OR REPLACE FUNCTION ops.acknowledge_alert(
    p_alert_id INTEGER,
    p_acknowledged_by VARCHAR(100) DEFAULT 'system'
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE ops.pipeline_alerts
    SET acknowledged_at = NOW(),
        acknowledged_by = p_acknowledged_by
    WHERE id = p_alert_id
      AND acknowledged_at IS NULL;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 7. Resolve Alert Function
-- ============================================================================
CREATE OR REPLACE FUNCTION ops.resolve_alert(p_alert_id INTEGER)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE ops.pipeline_alerts
    SET resolved_at = NOW()
    WHERE id = p_alert_id
      AND resolved_at IS NULL;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 8. Grant Permissions
-- ============================================================================
GRANT SELECT ON ops.pipeline_alerts TO nexus;
GRANT SELECT ON ops.v_pipeline_health TO nexus;
GRANT SELECT ON ops.v_active_alerts TO nexus;
GRANT SELECT ON ops.v_dashboard_health_summary TO nexus;
GRANT EXECUTE ON FUNCTION ops.check_pipeline_health() TO nexus;
GRANT EXECUTE ON FUNCTION ops.acknowledge_alert(INTEGER, VARCHAR) TO nexus;
GRANT EXECUTE ON FUNCTION ops.resolve_alert(INTEGER) TO nexus;
GRANT INSERT, UPDATE ON ops.pipeline_alerts TO nexus;
GRANT USAGE, SELECT ON SEQUENCE ops.pipeline_alerts_id_seq TO nexus;
