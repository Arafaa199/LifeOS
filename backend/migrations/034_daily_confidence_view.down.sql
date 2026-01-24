-- Migration: 034_daily_confidence_view (DOWN)
-- Purpose: Rollback TASK-M6.3 "Today Is Correct" Assertion

-- Restore original finance.get_dashboard_payload (from M6.2)
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

        -- Feeds status (M6.2)
        'feeds_status', feeds.data,

        -- Metadata
        'as_of_date', CURRENT_DATE,
        'generated_at', NOW()
    )
    FROM mtd
    CROSS JOIN budget_summary bs
    CROSS JOIN feeds;
$$;

-- Drop confidence function
DROP FUNCTION IF EXISTS life.get_today_confidence();

-- Drop confidence view
DROP VIEW IF EXISTS life.daily_confidence;
