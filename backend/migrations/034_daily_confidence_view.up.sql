-- Migration: 034_daily_confidence_view
-- Purpose: TASK-M6.3 "Today Is Correct" Assertion
-- Creates life.daily_confidence view with confidence scoring
-- Answers: "Is today accurate?" with a 0.0-1.0 confidence score

-- Create life.daily_confidence view
-- Calculates confidence score based on data completeness and feed health
CREATE OR REPLACE VIEW life.daily_confidence AS
WITH date_series AS (
    -- Generate last 30 days
    SELECT generate_series(
        CURRENT_DATE - INTERVAL '30 days',
        CURRENT_DATE,
        '1 day'::interval
    )::date AS day
),
daily_transactions AS (
    -- Transaction counts per day
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
    -- Receipt counts per day
    SELECT
        DATE(created_at AT TIME ZONE 'Asia/Dubai') AS day,
        COUNT(*) AS receipt_count
    FROM finance.receipts
    GROUP BY DATE(created_at AT TIME ZONE 'Asia/Dubai')
),
daily_health AS (
    -- WHOOP/Health data from life.daily_facts
    SELECT
        day,
        recovery_score IS NOT NULL AS has_whoop_recovery,
        sleep_minutes IS NOT NULL AND sleep_minutes > 0 AS has_whoop_sleep,
        hrv IS NOT NULL AND hrv > 0 AS has_whoop_hrv,
        weight_kg IS NOT NULL AS has_healthkit_weight
    FROM life.daily_facts
),
feed_status_today AS (
    -- Current feed health status
    SELECT
        COUNT(*) FILTER (WHERE status = 'OK') AS feeds_ok,
        COUNT(*) FILTER (WHERE status = 'STALE') AS feeds_stale,
        COUNT(*) FILTER (WHERE status = 'CRITICAL') AS feeds_critical,
        COUNT(*) AS feeds_total
    FROM system.feeds_status
),
confidence_calc AS (
    SELECT
        ds.day,

        -- Data presence flags
        COALESCE(dt.spend_count, 0) > 0 AS has_sms,
        COALESCE(dr.receipt_count, 0) > 0 AS has_receipts,
        COALESCE(dh.has_whoop_recovery, false) AS has_whoop,
        COALESCE(dh.has_healthkit_weight, false) AS has_healthkit,
        COALESCE(dt.income_count, 0) > 0 AS has_income,

        -- Raw counts for debugging
        COALESCE(dt.spend_count, 0) AS spend_count,
        COALESCE(dt.income_count, 0) AS income_count,
        COALESCE(dr.receipt_count, 0) AS receipt_count,

        -- Stale feeds count (only for today)
        CASE
            WHEN ds.day = CURRENT_DATE THEN fst.feeds_stale + fst.feeds_critical
            ELSE 0
        END AS stale_feeds,

        -- Confidence score calculation
        -- Start at 1.0, apply penalties
        GREATEST(0.0,
            1.0
            -- Core data penalties (only for today and yesterday)
            - CASE WHEN ds.day >= CURRENT_DATE - 1 AND COALESCE(dt.spend_count, 0) = 0
                   THEN 0.2 ELSE 0 END  -- Missing SMS/transactions
            - CASE WHEN ds.day >= CURRENT_DATE - 1 AND NOT COALESCE(dh.has_whoop_recovery, false)
                   THEN 0.2 ELSE 0 END  -- Missing WHOOP
            -- Feed health penalties (only for today)
            - CASE WHEN ds.day = CURRENT_DATE
                   THEN fst.feeds_stale * 0.1 ELSE 0 END  -- Stale feeds
            - CASE WHEN ds.day = CURRENT_DATE
                   THEN fst.feeds_critical * 0.15 ELSE 0 END  -- Critical feeds
        )::NUMERIC(3,2) AS confidence_score

    FROM date_series ds
    LEFT JOIN daily_transactions dt ON dt.day = ds.day
    LEFT JOIN daily_receipts dr ON dr.day = ds.day
    LEFT JOIN daily_health dh ON dh.day = ds.day
    CROSS JOIN feed_status_today fst
)
SELECT
    day,
    has_sms,
    has_receipts,
    has_whoop,
    has_healthkit,
    has_income,
    stale_feeds,
    confidence_score,
    -- Human-readable confidence level
    CASE
        WHEN confidence_score >= 0.9 THEN 'HIGH'
        WHEN confidence_score >= 0.7 THEN 'MEDIUM'
        WHEN confidence_score >= 0.5 THEN 'LOW'
        ELSE 'VERY_LOW'
    END AS confidence_level,
    -- Details for debugging
    spend_count,
    income_count,
    receipt_count
FROM confidence_calc
ORDER BY day DESC;

COMMENT ON VIEW life.daily_confidence IS 'Daily data confidence scoring for LifeOS dashboard (TASK-M6.3)';

-- Create function to get today's confidence for dashboard
CREATE OR REPLACE FUNCTION life.get_today_confidence()
RETURNS JSONB
LANGUAGE SQL
STABLE
AS $$
    SELECT jsonb_build_object(
        'date', day,
        'confidence_score', confidence_score,
        'confidence_level', confidence_level,
        'has_sms', has_sms,
        'has_receipts', has_receipts,
        'has_whoop', has_whoop,
        'has_healthkit', has_healthkit,
        'has_income', has_income,
        'stale_feeds', stale_feeds,
        'spend_count', spend_count,
        'income_count', income_count,
        'receipt_count', receipt_count
    )
    FROM life.daily_confidence
    WHERE day = CURRENT_DATE;
$$;

COMMENT ON FUNCTION life.get_today_confidence() IS 'Returns today''s confidence score for dashboard payload';

-- Update finance.get_dashboard_payload to include confidence_score
CREATE OR REPLACE FUNCTION finance.get_dashboard_payload()
RETURNS JSONB
LANGUAGE SQL
STABLE
AS $$
    WITH mtd AS (
        SELECT * FROM facts.month_to_date_summary
    ),
    budget_summary AS (
        SELECT * FROM facts.budget_status_summary
    ),
    feeds AS (
        SELECT system.get_feeds_summary() AS data
    ),
    confidence AS (
        SELECT life.get_today_confidence() AS data
    )
    SELECT jsonb_build_object(
        -- Core daily/MTD metrics
        'today_spent', COALESCE(mtd.today_spent, 0),
        'mtd_spent', COALESCE(mtd.mtd_spent, 0),
        'mtd_income', COALESCE(mtd.mtd_income, 0),
        'net_savings', COALESCE(mtd.mtd_net, 0),

        -- Top category
        'top_category', COALESCE(mtd.top_category, 'None'),
        'top_category_spent', COALESCE(mtd.top_category_spent, 0),

        -- Budget summary
        'budgets_over', COALESCE(bs.budgets_over, 0),
        'budgets_warning', COALESCE(bs.budgets_warning, 0),
        'budgets_healthy', COALESCE(bs.budgets_healthy, 0),
        'budgets_total', COALESCE(bs.budgets_total, 0),
        'total_budgeted', COALESCE(bs.total_budgeted, 0),
        'overall_budget_pct', COALESCE(bs.overall_pct_used, 0),

        -- Category breakdown (for charts)
        'spend_by_category', COALESCE(mtd.spend_by_category, '[]'::jsonb),

        -- Feeds status (M6.2)
        'feeds_status', feeds.data,

        -- Confidence score (NEW for M6.3)
        'confidence', confidence.data,

        -- Metadata
        'as_of_date', CURRENT_DATE,
        'generated_at', NOW()
    )
    FROM mtd
    CROSS JOIN budget_summary bs
    CROSS JOIN feeds
    CROSS JOIN confidence;
$$;

COMMENT ON FUNCTION finance.get_dashboard_payload() IS 'Complete finance dashboard payload including feeds status and confidence (M6.3)';
