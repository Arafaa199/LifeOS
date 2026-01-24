-- Migration: 031_finance_dashboard_function
-- Purpose: Create function that returns finance dashboard JSON payload
-- TASK: M1.3 - Add Finance Dashboard API Response
-- Created: 2026-01-24

-- ============================================================================
-- FINANCE DASHBOARD FUNCTION
-- Purpose: Single function that returns all finance dashboard data as JSON
-- Uses existing views: facts.month_to_date_summary, facts.budget_status_summary
-- ============================================================================

CREATE OR REPLACE FUNCTION finance.get_dashboard_payload()
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
    WITH mtd AS (
        SELECT * FROM facts.month_to_date_summary
    ),
    budget_summary AS (
        SELECT * FROM facts.budget_status_summary
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

        -- Metadata
        'as_of_date', CURRENT_DATE,
        'generated_at', NOW()
    )
    FROM mtd
    CROSS JOIN budget_summary bs;
$$;

COMMENT ON FUNCTION finance.get_dashboard_payload() IS
'Returns complete finance dashboard payload as JSON. Combines MTD summary and budget status.';


-- ============================================================================
-- GRANT PERMISSIONS (for n8n user if different)
-- ============================================================================

-- The nexus user already has access, but explicitly grant execute
GRANT EXECUTE ON FUNCTION finance.get_dashboard_payload() TO nexus;
