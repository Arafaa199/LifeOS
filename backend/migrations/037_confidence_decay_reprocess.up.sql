-- Migration 037: Confidence Decay + Reprocess Pipeline
-- TASK-A2: Confidence scores decay over time; stale data triggers reprocessing
-- Author: Claude Coder
-- Date: 2026-01-24

-- ============================================================================
-- 1. CONFIDENCE DECAY VIEW
-- Adds time-based decay to confidence scores based on feed staleness
-- Decay rate: -0.05 per hour that any feed is stale (beyond threshold)
-- ============================================================================

CREATE OR REPLACE VIEW life.daily_confidence_with_decay AS
WITH date_series AS (
    SELECT generate_series(
        CURRENT_DATE - INTERVAL '30 days',
        CURRENT_DATE,
        INTERVAL '1 day'
    )::date AS day
),
daily_transactions AS (
    SELECT
        finance.to_business_date(transaction_at) AS day,
        COUNT(*) FILTER (WHERE amount < 0 AND category != 'Transfer') AS spend_count,
        COUNT(*) FILTER (WHERE amount > 0) AS income_count,
        COUNT(*) AS total_count
    FROM finance.transactions
    WHERE is_quarantined = false
    GROUP BY finance.to_business_date(transaction_at)
),
daily_receipts AS (
    SELECT
        date(created_at AT TIME ZONE 'Asia/Dubai') AS day,
        COUNT(*) AS receipt_count
    FROM finance.receipts
    GROUP BY date(created_at AT TIME ZONE 'Asia/Dubai')
),
daily_health AS (
    SELECT
        day,
        recovery_score IS NOT NULL AS has_whoop_recovery,
        sleep_minutes IS NOT NULL AND sleep_minutes > 0 AS has_whoop_sleep,
        hrv IS NOT NULL AND hrv > 0 AS has_whoop_hrv,
        weight_kg IS NOT NULL AS has_healthkit_weight
    FROM life.daily_facts
),
feed_staleness AS (
    -- Calculate total staleness hours across all feeds
    SELECT
        SUM(
            GREATEST(0, hours_since - expected_frequency_hours)
        ) AS total_stale_hours,
        COUNT(*) FILTER (WHERE status = 'STALE') AS stale_count,
        COUNT(*) FILTER (WHERE status = 'CRITICAL') AS critical_count
    FROM system.feeds_status
    WHERE hours_since IS NOT NULL
),
confidence_calc AS (
    SELECT
        ds.day,
        COALESCE(dt.spend_count, 0) > 0 AS has_sms,
        COALESCE(dr.receipt_count, 0) > 0 AS has_receipts,
        COALESCE(dh.has_whoop_recovery, false) AS has_whoop,
        COALESCE(dh.has_healthkit_weight, false) AS has_healthkit,
        COALESCE(dt.income_count, 0) > 0 AS has_income,
        COALESCE(dt.spend_count, 0) AS spend_count,
        COALESCE(dt.income_count, 0) AS income_count,
        COALESCE(dr.receipt_count, 0) AS receipt_count,
        -- Base penalties (same as original)
        CASE WHEN ds.day = CURRENT_DATE THEN fs.stale_count + fs.critical_count ELSE 0 END AS stale_feeds,
        -- Base confidence (from M6.3)
        GREATEST(0.0, 1.0
            - CASE WHEN ds.day >= CURRENT_DATE - 1 AND COALESCE(dt.spend_count, 0) = 0 THEN 0.2 ELSE 0 END
            - CASE WHEN ds.day >= CURRENT_DATE - 1 AND NOT COALESCE(dh.has_whoop_recovery, false) THEN 0.2 ELSE 0 END
            - CASE WHEN ds.day = CURRENT_DATE THEN fs.stale_count * 0.1 ELSE 0 END
            - CASE WHEN ds.day = CURRENT_DATE THEN fs.critical_count * 0.15 ELSE 0 END
        ) AS base_confidence,
        -- Decay: -0.05 per hour of total staleness (for today only)
        CASE
            WHEN ds.day = CURRENT_DATE THEN
                GREATEST(0, COALESCE(fs.total_stale_hours, 0))
            ELSE 0
        END AS total_stale_hours
    FROM date_series ds
    LEFT JOIN daily_transactions dt ON dt.day = ds.day
    LEFT JOIN daily_receipts dr ON dr.day = ds.day
    LEFT JOIN daily_health dh ON dh.day = ds.day
    CROSS JOIN feed_staleness fs
)
SELECT
    day,
    has_sms,
    has_receipts,
    has_whoop,
    has_healthkit,
    has_income,
    stale_feeds,
    base_confidence::NUMERIC(3,2) AS base_confidence,
    -- Apply decay: -0.05 per stale hour, capped at reducing to 0
    GREATEST(0.0, base_confidence - (total_stale_hours * 0.05))::NUMERIC(3,2) AS confidence_score,
    (total_stale_hours * 0.05)::NUMERIC(4,2) AS decay_penalty,
    total_stale_hours::NUMERIC(6,1) AS stale_hours,
    CASE
        WHEN GREATEST(0.0, base_confidence - (total_stale_hours * 0.05)) >= 0.9 THEN 'HIGH'
        WHEN GREATEST(0.0, base_confidence - (total_stale_hours * 0.05)) >= 0.7 THEN 'MEDIUM'
        WHEN GREATEST(0.0, base_confidence - (total_stale_hours * 0.05)) >= 0.5 THEN 'LOW'
        ELSE 'VERY_LOW'
    END AS confidence_level,
    spend_count,
    income_count,
    receipt_count
FROM confidence_calc
ORDER BY day DESC;

COMMENT ON VIEW life.daily_confidence_with_decay IS
'Daily confidence scores with time-based decay. Decay rate: -0.05 per hour that feeds are stale beyond their threshold.';

-- ============================================================================
-- 2. REPROCESS QUEUE VIEW
-- Identifies days that need reprocessing based on staleness or data gaps
-- ============================================================================

CREATE OR REPLACE VIEW ops.reprocess_queue AS
WITH recent_days AS (
    SELECT generate_series(
        CURRENT_DATE - INTERVAL '7 days',
        CURRENT_DATE,
        INTERVAL '1 day'
    )::date AS day
),
day_facts AS (
    SELECT
        day,
        computed_at,
        recovery_score IS NOT NULL AS has_recovery,
        sleep_minutes IS NOT NULL AND sleep_minutes > 0 AS has_sleep,
        spend_total IS NOT NULL AS has_spend,
        income_total IS NOT NULL AS has_income
    FROM life.daily_facts
),
transaction_counts AS (
    SELECT
        finance.to_business_date(transaction_at) AS day,
        COUNT(*) AS tx_count,
        MAX(created_at) AS last_tx_created
    FROM finance.transactions
    WHERE is_quarantined = false
    GROUP BY finance.to_business_date(transaction_at)
),
stale_sources AS (
    SELECT
        feed_name,
        hours_since,
        expected_frequency_hours,
        status,
        -- Source needs refresh if stale or critical
        status IN ('STALE', 'CRITICAL') AS needs_refresh
    FROM system.feeds_status
),
reprocess_reasons AS (
    SELECT
        rd.day,
        -- Check if daily_facts was computed after transactions were created
        CASE
            WHEN df.computed_at IS NULL THEN 'no_facts_record'
            WHEN tc.last_tx_created IS NOT NULL AND df.computed_at < tc.last_tx_created THEN 'facts_stale_vs_transactions'
            ELSE NULL
        END AS facts_stale_reason,
        -- Check if any source is stale
        EXISTS (SELECT 1 FROM stale_sources WHERE needs_refresh) AS has_stale_sources,
        -- Check if data is missing
        NOT COALESCE(df.has_spend, false) AND rd.day = CURRENT_DATE AS missing_today_spend,
        NOT COALESCE(df.has_recovery, false) AND rd.day >= CURRENT_DATE - 1 AS missing_recent_recovery,
        -- Hours since daily_facts was computed
        EXTRACT(EPOCH FROM (NOW() - COALESCE(df.computed_at, NOW() - INTERVAL '999 days'))) / 3600 AS hours_since_facts_update,
        tc.tx_count,
        df.computed_at AS facts_computed_at,
        tc.last_tx_created
    FROM recent_days rd
    LEFT JOIN day_facts df ON df.day = rd.day
    LEFT JOIN transaction_counts tc ON tc.day = rd.day
)
SELECT
    day,
    CASE
        WHEN facts_stale_reason IS NOT NULL THEN facts_stale_reason
        WHEN missing_today_spend THEN 'missing_today_spend'
        WHEN missing_recent_recovery THEN 'missing_recent_recovery'
        WHEN has_stale_sources AND day = CURRENT_DATE THEN 'stale_source_feeds'
        WHEN hours_since_facts_update > 24 AND day >= CURRENT_DATE - 3 THEN 'facts_too_old'
        ELSE NULL
    END AS reason,
    hours_since_facts_update::NUMERIC(8,1) AS hours_since_update,
    COALESCE(tx_count, 0) AS transaction_count,
    facts_computed_at,
    last_tx_created AS transactions_created_at,
    -- Priority: higher = more urgent
    CASE
        WHEN facts_stale_reason = 'no_facts_record' THEN 100
        WHEN facts_stale_reason = 'facts_stale_vs_transactions' THEN 90
        WHEN missing_today_spend THEN 80
        WHEN missing_recent_recovery THEN 70
        WHEN has_stale_sources AND day = CURRENT_DATE THEN 60
        WHEN hours_since_facts_update > 24 THEN 50
        ELSE 0
    END AS priority
FROM reprocess_reasons
WHERE
    facts_stale_reason IS NOT NULL
    OR missing_today_spend
    OR missing_recent_recovery
    OR (has_stale_sources AND day = CURRENT_DATE)
    OR (hours_since_facts_update > 24 AND day >= CURRENT_DATE - 3)
ORDER BY priority DESC, day DESC;

COMMENT ON VIEW ops.reprocess_queue IS
'Days that need reprocessing, with reason and priority. Priority 100 = highest urgency.';

-- ============================================================================
-- 3. REPROCESS FUNCTION
-- Consumes the queue and rebuilds affected days
-- ============================================================================

CREATE OR REPLACE FUNCTION ops.reprocess_stale_days(max_days INTEGER DEFAULT 7)
RETURNS TABLE (
    day DATE,
    reason TEXT,
    status TEXT,
    duration_ms INTEGER
) AS $$
DECLARE
    rec RECORD;
    start_time TIMESTAMPTZ;
    result_status TEXT;
BEGIN
    FOR rec IN
        SELECT rq.day, rq.reason, rq.priority
        FROM ops.reprocess_queue rq
        ORDER BY rq.priority DESC, rq.day DESC
        LIMIT max_days
    LOOP
        start_time := clock_timestamp();
        result_status := 'success';

        BEGIN
            -- Refresh daily_facts for this day
            PERFORM life.refresh_daily_facts(rec.day);

            -- Refresh finance summary for this day
            PERFORM insights.generate_daily_summary(rec.day);

        EXCEPTION WHEN OTHERS THEN
            result_status := 'error: ' || SQLERRM;
        END;

        day := rec.day;
        reason := rec.reason;
        status := result_status;
        duration_ms := EXTRACT(MILLISECONDS FROM (clock_timestamp() - start_time))::INTEGER;

        RETURN NEXT;
    END LOOP;

    RETURN;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ops.reprocess_stale_days IS
'Reprocesses days from the reprocess queue. Returns status per day processed.';

-- ============================================================================
-- 4. HELPER: Get Confidence with Decay for Today
-- ============================================================================

CREATE OR REPLACE FUNCTION life.get_today_confidence_with_decay()
RETURNS JSONB AS $$
    SELECT jsonb_build_object(
        'date', day,
        'has_sms', has_sms,
        'has_receipts', has_receipts,
        'has_whoop', has_whoop,
        'has_healthkit', has_healthkit,
        'has_income', has_income,
        'stale_feeds', stale_feeds,
        'base_confidence', base_confidence,
        'confidence_score', confidence_score,
        'decay_penalty', decay_penalty,
        'stale_hours', stale_hours,
        'confidence_level', confidence_level,
        'spend_count', spend_count,
        'income_count', income_count,
        'receipt_count', receipt_count
    )
    FROM life.daily_confidence_with_decay
    WHERE day = CURRENT_DATE;
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION life.get_today_confidence_with_decay IS
'Returns today''s confidence score with decay as JSON.';

-- ============================================================================
-- 5. SUMMARY VIEW: Reprocess Queue Summary
-- ============================================================================

CREATE OR REPLACE VIEW ops.reprocess_queue_summary AS
SELECT
    COUNT(*) AS total_days_queued,
    COUNT(*) FILTER (WHERE priority >= 80) AS urgent_count,
    COUNT(*) FILTER (WHERE priority >= 50 AND priority < 80) AS moderate_count,
    COUNT(*) FILTER (WHERE priority > 0 AND priority < 50) AS low_count,
    MAX(priority) AS max_priority,
    MIN(day) AS oldest_queued_day,
    MAX(day) AS newest_queued_day,
    CASE
        WHEN COUNT(*) = 0 THEN 'HEALTHY'
        WHEN MAX(priority) >= 80 THEN 'CRITICAL'
        WHEN MAX(priority) >= 50 THEN 'WARNING'
        ELSE 'OK'
    END AS queue_status
FROM ops.reprocess_queue
WHERE reason IS NOT NULL;

COMMENT ON VIEW ops.reprocess_queue_summary IS
'Summary of reprocess queue status for dashboard monitoring.';

