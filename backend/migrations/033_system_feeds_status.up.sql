-- Migration: 033_system_feeds_status
-- Purpose: TASK-M6.2 Feed Health Truth Table
-- Creates system.feeds_status view for dashboard to show feed health
-- Status values: OK, STALE, CRITICAL (standardized from ops.v_pipeline_health)

-- Create system schema if not exists
CREATE SCHEMA IF NOT EXISTS system;

-- Create canonical feeds_status view
-- Wraps ops.v_pipeline_health with standardized column names per M6.2 spec
CREATE OR REPLACE VIEW system.feeds_status AS
SELECT
    source AS feed_name,
    last_event_at,
    hours_since_last AS hours_since,
    EXTRACT(EPOCH FROM expected_frequency) / 3600.0 AS expected_frequency_hours,
    CASE status
        WHEN 'ok' THEN 'OK'
        WHEN 'stale' THEN 'STALE'
        WHEN 'critical' THEN 'CRITICAL'
        WHEN 'never' THEN 'CRITICAL'  -- never seen = critical
        ELSE 'CRITICAL'
    END AS status,
    domain,
    events_24h,
    notes
FROM ops.v_pipeline_health
ORDER BY
    CASE status
        WHEN 'critical' THEN 1
        WHEN 'never' THEN 1
        WHEN 'stale' THEN 2
        WHEN 'ok' THEN 3
    END,
    feed_name;

COMMENT ON VIEW system.feeds_status IS 'Canonical feed health status for dashboard (TASK-M6.2)';

-- Create function to get feeds summary for dashboard
CREATE OR REPLACE FUNCTION system.get_feeds_summary()
RETURNS JSONB
LANGUAGE SQL
STABLE
AS $$
    SELECT jsonb_build_object(
        'feeds', (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'feed_name', feed_name,
                    'status', status,
                    'hours_since', ROUND(hours_since::numeric, 1),
                    'last_event_at', last_event_at
                )
                ORDER BY
                    CASE status
                        WHEN 'CRITICAL' THEN 1
                        WHEN 'STALE' THEN 2
                        WHEN 'OK' THEN 3
                    END,
                    feed_name
            )
            FROM system.feeds_status
        ),
        'feeds_ok', COUNT(*) FILTER (WHERE status = 'OK'),
        'feeds_stale', COUNT(*) FILTER (WHERE status = 'STALE'),
        'feeds_critical', COUNT(*) FILTER (WHERE status = 'CRITICAL'),
        'feeds_total', COUNT(*),
        'overall_status', CASE
            WHEN COUNT(*) FILTER (WHERE status = 'CRITICAL') > 0 THEN 'CRITICAL'
            WHEN COUNT(*) FILTER (WHERE status = 'STALE') > 0 THEN 'STALE'
            ELSE 'OK'
        END,
        'checked_at', NOW()
    )
    FROM system.feeds_status;
$$;

COMMENT ON FUNCTION system.get_feeds_summary() IS 'Returns feeds status summary for dashboard payload';

-- Update finance.get_dashboard_payload to include feeds_status
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

        -- Feeds status (NEW for M6.2)
        'feeds_status', feeds.data,

        -- Metadata
        'as_of_date', CURRENT_DATE,
        'generated_at', NOW()
    )
    FROM mtd
    CROSS JOIN budget_summary bs
    CROSS JOIN feeds;
$$;

COMMENT ON FUNCTION finance.get_dashboard_payload() IS 'Complete finance dashboard payload including feeds status (M6.2)';
