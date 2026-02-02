-- Migration 133: Add missing is_quarantined filter to dashboard finance summary
-- The current_month and top_categories CTEs in v_dashboard_finance_summary
-- were missing the quarantine filter, inflating spend totals with quarantined transactions.

BEGIN;

CREATE OR REPLACE VIEW finance.v_dashboard_finance_summary AS
WITH current_month AS (
    SELECT
        SUM(CASE WHEN COALESCE(amount_preferred, amount) < 0 THEN ABS(COALESCE(amount_preferred, amount)) ELSE 0 END) AS total_spend,
        SUM(CASE WHEN COALESCE(amount_preferred, amount) > 0 THEN COALESCE(amount_preferred, amount) ELSE 0 END) AS total_income,
        COUNT(*) FILTER (WHERE amount < 0) AS expense_count,
        COUNT(*) FILTER (WHERE amount > 0) AS income_count
    FROM finance.transactions
    WHERE date_trunc('month', date::timestamptz) = date_trunc('month', CURRENT_DATE::timestamptz)
      AND is_quarantined IS NOT TRUE
      AND pairing_role IS DISTINCT FROM 'fx_metadata'
      AND category NOT IN ('Transfer', 'CC Payment', 'BNPL Repayment', 'Credit Card Payment')
), top_categories AS (
    SELECT category,
        SUM(ABS(COALESCE(amount_preferred, amount))) AS spend,
        COUNT(*) AS count
    FROM finance.transactions
    WHERE amount < 0
      AND date_trunc('month', date::timestamptz) = date_trunc('month', CURRENT_DATE::timestamptz)
      AND is_quarantined IS NOT TRUE
      AND pairing_role IS DISTINCT FROM 'fx_metadata'
      AND category NOT IN ('Transfer', 'CC Payment', 'BNPL Repayment', 'Credit Card Payment')
    GROUP BY category
    ORDER BY SUM(ABS(COALESCE(amount_preferred, amount))) DESC
    LIMIT 5
), anomaly_summary AS (
    SELECT
        COUNT(*) FILTER (WHERE anomaly_level = 'severe_anomaly') AS severe_count,
        COUNT(*) FILTER (WHERE anomaly_level = 'anomaly') AS anomaly_count,
        COUNT(*) FILTER (WHERE anomaly_level = 'elevated') AS elevated_count
    FROM finance.mv_spending_anomalies
    WHERE date >= date_trunc('month', CURRENT_DATE::timestamptz)
)
SELECT
    cm.total_spend AS month_spend,
    cm.total_income AS month_income,
    cm.expense_count,
    cm.income_count,
    cm.total_income - cm.total_spend AS month_net,
    (SELECT jsonb_agg(jsonb_build_object('category', category, 'spend', spend, 'count', count)) FROM top_categories) AS top_categories,
    (SELECT stability_rating FROM finance.mv_income_stability LIMIT 1) AS income_stability,
    (SELECT cv_pct FROM finance.mv_income_stability LIMIT 1) AS income_cv_pct,
    ans.severe_count AS anomalies_severe,
    ans.anomaly_count AS anomalies_moderate,
    ans.elevated_count AS anomalies_elevated,
    CASE
        WHEN ans.severe_count > 0 THEN 'warning'
        WHEN ans.anomaly_count > 2 THEN 'caution'
        WHEN cm.total_spend > cm.total_income AND cm.total_income > 0 THEN 'overspend'
        ELSE 'healthy'
    END AS health_status,
    CURRENT_TIMESTAMP AS generated_at
FROM current_month cm
CROSS JOIN anomaly_summary ans;

COMMIT;
