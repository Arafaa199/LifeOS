-- Migration: 030_budget_status_view
-- Purpose: Create budget status view for tracking spending against budget limits
-- TASK: M1.2 - Implement Budgets + Budget Status View
-- Created: 2026-01-24

-- ============================================================================
-- BUDGET STATUS VIEW
-- Purpose: Shows each budget with its current spending, remaining, and status
-- Status thresholds:
--   - healthy: < 80% used
--   - warning: 80-100% used
--   - over: > 100% used
-- ============================================================================

CREATE OR REPLACE VIEW facts.budget_status AS
WITH current_month AS (
    SELECT DATE_TRUNC('month', CURRENT_DATE AT TIME ZONE 'Asia/Dubai')::DATE AS month_start
),
mtd_spend_by_category AS (
    -- Get MTD spending per category
    SELECT
        category,
        SUM(ABS(amount)) AS spent
    FROM finance.transactions, current_month cm
    WHERE amount < 0                      -- Expenses only
      AND is_quarantined = false          -- Exclude quarantined
      AND category != 'Transfer'          -- Exclude transfers
      AND finance.to_business_date(transaction_at) >= cm.month_start
      AND finance.to_business_date(transaction_at) <= CURRENT_DATE
    GROUP BY category
)
SELECT
    b.id AS budget_id,
    b.category,
    b.budget_amount AS monthly_limit,
    COALESCE(s.spent, 0) AS spent,
    b.budget_amount - COALESCE(s.spent, 0) AS remaining,
    CASE
        WHEN b.budget_amount = 0 THEN 0
        ELSE ROUND((COALESCE(s.spent, 0) / b.budget_amount) * 100, 1)
    END AS pct_used,
    CASE
        WHEN b.budget_amount = 0 THEN 'no_budget'
        WHEN (COALESCE(s.spent, 0) / b.budget_amount) * 100 > 100 THEN 'over'
        WHEN (COALESCE(s.spent, 0) / b.budget_amount) * 100 >= 80 THEN 'warning'
        ELSE 'healthy'
    END AS status,
    b.alert_threshold_pct,
    b.notes,
    CURRENT_DATE AS as_of_date
FROM finance.budgets b
CROSS JOIN current_month cm
LEFT JOIN mtd_spend_by_category s ON LOWER(b.category) = LOWER(s.category)
WHERE b.month = cm.month_start
ORDER BY
    CASE
        WHEN (COALESCE(s.spent, 0) / NULLIF(b.budget_amount, 0)) * 100 > 100 THEN 1  -- over first
        WHEN (COALESCE(s.spent, 0) / NULLIF(b.budget_amount, 0)) * 100 >= 80 THEN 2  -- warning second
        ELSE 3                                                                        -- healthy last
    END,
    COALESCE(s.spent, 0) DESC;  -- Then by amount spent

COMMENT ON VIEW facts.budget_status IS
'Budget status for current month. Shows spending vs limit with status indicators (healthy/warning/over). Ordered by urgency.';


-- ============================================================================
-- BUDGET STATUS SUMMARY VIEW
-- Purpose: Aggregated counts for dashboard (how many healthy/warning/over)
-- ============================================================================

CREATE OR REPLACE VIEW facts.budget_status_summary AS
SELECT
    COUNT(*) FILTER (WHERE status = 'healthy') AS budgets_healthy,
    COUNT(*) FILTER (WHERE status = 'warning') AS budgets_warning,
    COUNT(*) FILTER (WHERE status = 'over') AS budgets_over,
    COUNT(*) AS budgets_total,
    SUM(monthly_limit) AS total_budgeted,
    SUM(spent) AS total_spent,
    SUM(monthly_limit) - SUM(spent) AS total_remaining,
    ROUND(SUM(spent) / NULLIF(SUM(monthly_limit), 0) * 100, 1) AS overall_pct_used,
    CURRENT_DATE AS as_of_date
FROM facts.budget_status;

COMMENT ON VIEW facts.budget_status_summary IS
'Summary counts of budget statuses for dashboard display. Shows healthy/warning/over counts and overall utilization.';
