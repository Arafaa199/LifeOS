-- Migration 038: Finance Budget Engine View
-- TASK-B1: Implement Read-Only Budget Engine (No Alerts)
-- Created: 2026-01-24
--
-- Objective: Budget tracking with pace calculation — just facts, no alerts.
-- Pace answers: "If I continue at this rate, will I exceed my budget?"

-- Drop existing view if it exists (idempotent)
DROP VIEW IF EXISTS finance.budget_engine CASCADE;

-- Create the budget engine view
CREATE OR REPLACE VIEW finance.budget_engine AS
WITH month_context AS (
    -- Calculate month boundaries and progress
    SELECT
        date_trunc('month', CURRENT_DATE AT TIME ZONE 'Asia/Dubai')::date AS month_start,
        (date_trunc('month', CURRENT_DATE AT TIME ZONE 'Asia/Dubai') + INTERVAL '1 month - 1 day')::date AS month_end,
        EXTRACT(day FROM CURRENT_DATE AT TIME ZONE 'Asia/Dubai')::integer AS days_elapsed,
        EXTRACT(day FROM (date_trunc('month', CURRENT_DATE AT TIME ZONE 'Asia/Dubai') + INTERVAL '1 month - 1 day')::date)::integer AS days_in_month
),
mtd_spend AS (
    -- Get month-to-date spending per category
    SELECT
        t.category,
        SUM(ABS(t.amount)) AS spent,
        COUNT(*) AS transaction_count
    FROM finance.transactions t
    CROSS JOIN month_context mc
    WHERE t.amount < 0
      AND t.is_quarantined = FALSE
      AND t.category != 'Transfer'
      AND finance.to_business_date(t.transaction_at) >= mc.month_start
      AND finance.to_business_date(t.transaction_at) <= CURRENT_DATE
    GROUP BY t.category
)
SELECT
    b.id AS budget_id,
    b.category,
    b.budget_amount AS budgeted,
    COALESCE(s.spent, 0) AS spent,
    b.budget_amount - COALESCE(s.spent, 0) AS remaining,

    -- Percentage calculations
    CASE
        WHEN b.budget_amount = 0 THEN 0
        ELSE ROUND(COALESCE(s.spent, 0) / b.budget_amount * 100, 1)
    END AS pct_used,

    ROUND(mc.days_elapsed::numeric / mc.days_in_month * 100, 1) AS pct_month_elapsed,

    -- Projected spending at current rate
    CASE
        WHEN mc.days_elapsed = 0 THEN 0
        ELSE ROUND(COALESCE(s.spent, 0) / mc.days_elapsed * mc.days_in_month, 2)
    END AS projected_spend,

    -- Projected remaining (can be negative = projected over-budget)
    CASE
        WHEN mc.days_elapsed = 0 THEN b.budget_amount
        ELSE ROUND(b.budget_amount - (COALESCE(s.spent, 0) / mc.days_elapsed * mc.days_in_month), 2)
    END AS projected_remaining,

    -- Daily rate metrics
    CASE
        WHEN mc.days_elapsed = 0 THEN 0
        ELSE ROUND(COALESCE(s.spent, 0) / mc.days_elapsed, 2)
    END AS daily_avg_spend,

    CASE
        WHEN mc.days_in_month = 0 THEN 0
        ELSE ROUND(b.budget_amount / mc.days_in_month, 2)
    END AS daily_budget_target,

    -- Pace calculation: on_track, ahead (under budget), behind (over budget)
    CASE
        WHEN b.budget_amount = 0 THEN 'no_budget'
        WHEN COALESCE(s.spent, 0) / b.budget_amount * 100 > 100 THEN 'behind'  -- Already over budget
        WHEN mc.days_elapsed = 0 THEN 'on_track'  -- First day of month
        ELSE
            CASE
                -- Compare actual spend % vs expected spend %
                -- Expected spend % = days_elapsed / days_in_month * 100
                WHEN (COALESCE(s.spent, 0) / b.budget_amount * 100) <
                     (mc.days_elapsed::numeric / mc.days_in_month * 100 - 10) THEN 'ahead'
                WHEN (COALESCE(s.spent, 0) / b.budget_amount * 100) >
                     (mc.days_elapsed::numeric / mc.days_in_month * 100 + 10) THEN 'behind'
                ELSE 'on_track'
            END
    END AS pace,

    -- Additional context
    COALESCE(s.transaction_count, 0) AS transaction_count,
    mc.days_elapsed,
    mc.days_in_month,
    mc.days_in_month - mc.days_elapsed AS days_remaining,

    CURRENT_DATE AS as_of_date
FROM finance.budgets b
CROSS JOIN month_context mc
LEFT JOIN mtd_spend s ON LOWER(b.category) = LOWER(s.category)
WHERE b.month = mc.month_start
ORDER BY
    -- Order by pace urgency: behind first, then by projected overage
    CASE
        WHEN (COALESCE(s.spent, 0) / NULLIF(b.budget_amount, 0) * 100) > 100 THEN 1
        WHEN COALESCE(s.spent, 0) / NULLIF(b.budget_amount, 0) * 100 >
             (mc.days_elapsed::numeric / mc.days_in_month * 100 + 10) THEN 2
        ELSE 3
    END,
    COALESCE(s.spent, 0) DESC;

-- Summary view for dashboard consumption
DROP VIEW IF EXISTS finance.budget_engine_summary CASCADE;

CREATE OR REPLACE VIEW finance.budget_engine_summary AS
SELECT
    COUNT(*) FILTER (WHERE pace = 'ahead') AS budgets_ahead,
    COUNT(*) FILTER (WHERE pace = 'on_track') AS budgets_on_track,
    COUNT(*) FILTER (WHERE pace = 'behind') AS budgets_behind,
    COUNT(*) FILTER (WHERE pace = 'no_budget') AS budgets_no_limit,
    COUNT(*) AS budgets_total,
    SUM(budgeted) AS total_budgeted,
    SUM(spent) AS total_spent,
    SUM(projected_spend) AS total_projected,
    ROUND(AVG(pct_used), 1) AS avg_pct_used,
    -- Overall pace status
    CASE
        WHEN COUNT(*) FILTER (WHERE pace = 'behind') > 3 THEN 'critical'
        WHEN COUNT(*) FILTER (WHERE pace = 'behind') > 0 THEN 'warning'
        ELSE 'healthy'
    END AS overall_pace_status
FROM finance.budget_engine;

COMMENT ON VIEW finance.budget_engine IS 'Read-only budget tracking with pace calculation. Answers: If spending continues at this rate, will budget be exceeded?';
COMMENT ON VIEW finance.budget_engine_summary IS 'Aggregated budget engine summary for dashboard';
