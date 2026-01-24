-- Migration 033: Budget Alerts Enhancement
-- Purpose: Add alert thresholds to budgets and create alerting function
-- Created: 2026-01-24
-- Task: TASK-072

-- ============================================================================
-- 1. Add alert_threshold_pct column to budgets
-- ============================================================================
ALTER TABLE finance.budgets
ADD COLUMN IF NOT EXISTS alert_threshold_pct NUMERIC(5,2) DEFAULT 80.00;

COMMENT ON COLUMN finance.budgets.alert_threshold_pct IS 'Percentage threshold to trigger budget warning alert (default 80%)';

-- ============================================================================
-- 2. Enhanced Budget Status View (with alert status)
-- ============================================================================
CREATE OR REPLACE VIEW finance.v_budget_status AS
WITH current_month AS (
    SELECT date_trunc('month', CURRENT_DATE)::date AS month_start
),
budget_spending AS (
    SELECT
        b.id AS budget_id,
        b.category,
        b.budget_amount,
        b.alert_threshold_pct,
        COALESCE(SUM(ABS(t.amount)) FILTER (
            WHERE t.amount < 0
              AND t.category = b.category
              AND t.is_hidden = false
              AND t.is_quarantined = false
        ), 0) AS spent,
        COUNT(t.id) FILTER (
            WHERE t.amount < 0
              AND t.category = b.category
              AND t.is_hidden = false
        ) AS txn_count
    FROM finance.budgets b
    CROSS JOIN current_month cm
    LEFT JOIN finance.transactions t ON t.date >= cm.month_start AND t.date <= CURRENT_DATE
    WHERE b.month = cm.month_start
    GROUP BY b.id, b.category, b.budget_amount, b.alert_threshold_pct
)
SELECT
    budget_id,
    category,
    budget_amount AS monthly_limit,
    spent,
    budget_amount - spent AS remaining,
    txn_count,
    ROUND((spent / NULLIF(budget_amount, 0)) * 100, 1) AS pct_used,
    alert_threshold_pct,
    CASE
        WHEN spent >= budget_amount THEN 'over_budget'
        WHEN (spent / NULLIF(budget_amount, 0)) * 100 >= alert_threshold_pct THEN 'warning'
        WHEN (spent / NULLIF(budget_amount, 0)) * 100 >= 50 THEN 'on_track'
        ELSE 'healthy'
    END AS status,
    CASE
        WHEN spent >= budget_amount THEN TRUE
        WHEN (spent / NULLIF(budget_amount, 0)) * 100 >= alert_threshold_pct THEN TRUE
        ELSE FALSE
    END AS needs_alert
FROM budget_spending
ORDER BY pct_used DESC;

COMMENT ON VIEW finance.v_budget_status IS 'Current month budget status with alert thresholds';

-- ============================================================================
-- 3. Budget Alerts Check Function
-- ============================================================================
CREATE OR REPLACE FUNCTION finance.check_budget_alerts()
RETURNS TABLE(category TEXT, budget_status TEXT, alert_created BOOLEAN) AS $fn$
DECLARE
    rec RECORD;
    v_alert_created BOOLEAN;
BEGIN
    FOR rec IN
        SELECT bs.category, bs.monthly_limit, bs.spent, bs.pct_used, bs.status, bs.needs_alert
        FROM finance.v_budget_status bs
        WHERE bs.needs_alert = TRUE
    LOOP
        v_alert_created := FALSE;

        -- Check if alert already exists for this category this month
        IF NOT EXISTS (
            SELECT 1 FROM ops.pipeline_alerts a
            WHERE a.source = 'budget_' || rec.category
              AND a.alert_type IN ('budget_warning', 'budget_exceeded')
              AND a.resolved_at IS NULL
              AND a.created_at >= date_trunc('month', CURRENT_DATE)
        ) THEN
            INSERT INTO ops.pipeline_alerts (alert_type, source, severity, message, metadata)
            VALUES (
                CASE WHEN rec.status = 'over_budget' THEN 'budget_exceeded' ELSE 'budget_warning' END,
                'budget_' || rec.category,
                CASE WHEN rec.status = 'over_budget' THEN 'critical' ELSE 'warning' END,
                format('%s budget: %s%% used (%s of %s)',
                    rec.category,
                    rec.pct_used,
                    rec.spent,
                    rec.monthly_limit
                ),
                jsonb_build_object(
                    'category', rec.category,
                    'limit', rec.monthly_limit,
                    'spent', rec.spent,
                    'pct_used', rec.pct_used,
                    'status', rec.status
                )
            );
            v_alert_created := TRUE;
        END IF;

        category := rec.category;
        budget_status := rec.status;
        alert_created := v_alert_created;
        RETURN NEXT;
    END LOOP;

    -- Auto-resolve budget alerts for categories now under threshold
    UPDATE ops.pipeline_alerts a
    SET resolved_at = NOW()
    WHERE a.resolved_at IS NULL
      AND a.alert_type IN ('budget_warning', 'budget_exceeded')
      AND NOT EXISTS (
          SELECT 1 FROM finance.v_budget_status bs
          WHERE 'budget_' || bs.category = a.source
            AND bs.needs_alert = TRUE
      );

    RETURN;
END;
$fn$ LANGUAGE plpgsql;

COMMENT ON FUNCTION finance.check_budget_alerts() IS 'Check all budgets and create alerts for those exceeding thresholds';

-- ============================================================================
-- 4. Budget Summary View (for dashboard)
-- ============================================================================
CREATE OR REPLACE VIEW finance.v_budget_summary AS
SELECT
    COUNT(*) AS total_budgets,
    COUNT(*) FILTER (WHERE status = 'healthy') AS healthy,
    COUNT(*) FILTER (WHERE status = 'on_track') AS on_track,
    COUNT(*) FILTER (WHERE status = 'warning') AS warning,
    COUNT(*) FILTER (WHERE status = 'over_budget') AS over_budget,
    SUM(monthly_limit) AS total_budget,
    SUM(spent) AS total_spent,
    ROUND(SUM(spent) / NULLIF(SUM(monthly_limit), 0) * 100, 1) AS overall_pct_used,
    CASE
        WHEN COUNT(*) FILTER (WHERE status = 'over_budget') > 0 THEN 'CRITICAL'
        WHEN COUNT(*) FILTER (WHERE status = 'warning') > 2 THEN 'WARNING'
        ELSE 'HEALTHY'
    END AS overall_status
FROM finance.v_budget_status;

COMMENT ON VIEW finance.v_budget_summary IS 'High-level budget summary for dashboard';

-- ============================================================================
-- 5. Grant Permissions
-- ============================================================================
GRANT SELECT ON finance.v_budget_status TO nexus;
GRANT SELECT ON finance.v_budget_summary TO nexus;
GRANT EXECUTE ON FUNCTION finance.check_budget_alerts() TO nexus;
