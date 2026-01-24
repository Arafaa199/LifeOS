-- Migration: 022_financial_truth_layer
-- Purpose: Materialized views for financial insights: monthly spend, category velocity, income stability, anomaly detection
-- Created: 2026-01-23

-- ============================================================================
-- 1. MONTHLY SPEND BY CATEGORY (Materialized)
-- ============================================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS finance.mv_monthly_spend AS
SELECT
    DATE_TRUNC('month', date)::DATE as month,
    category,
    COUNT(*) as transaction_count,
    SUM(ABS(amount)) as total_spend,
    ROUND(AVG(ABS(amount)), 2) as avg_transaction,
    MIN(ABS(amount)) as min_transaction,
    MAX(ABS(amount)) as max_transaction,
    ROUND(STDDEV(ABS(amount)), 2) as stddev_amount
FROM finance.transactions
WHERE amount < 0  -- Expenses only
GROUP BY DATE_TRUNC('month', date)::DATE, category
ORDER BY month DESC, total_spend DESC;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_monthly_spend_pk
    ON finance.mv_monthly_spend(month, category);

COMMENT ON MATERIALIZED VIEW finance.mv_monthly_spend IS
'Monthly spending aggregated by category - refresh nightly';


-- ============================================================================
-- 2. CATEGORY VELOCITY (Spending rate and trend)
-- ============================================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS finance.mv_category_velocity AS
WITH monthly_totals AS (
    SELECT
        category,
        DATE_TRUNC('month', date)::DATE as month,
        SUM(ABS(amount)) as spend
    FROM finance.transactions
    WHERE amount < 0
    GROUP BY category, DATE_TRUNC('month', date)::DATE
),
category_stats AS (
    SELECT
        category,
        COUNT(DISTINCT month) as months_active,
        SUM(spend) as total_all_time,
        ROUND(AVG(spend), 2) as avg_monthly_spend,
        ROUND(STDDEV(spend), 2) as monthly_stddev,
        MIN(month) as first_month,
        MAX(month) as last_month
    FROM monthly_totals
    GROUP BY category
),
recent_trend AS (
    SELECT
        category,
        -- Last 3 months average
        ROUND(AVG(spend) FILTER (WHERE month >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '3 months'), 2) as recent_avg,
        -- Previous 3 months average (months 4-6 ago)
        ROUND(AVG(spend) FILTER (WHERE month >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6 months'
                                   AND month < DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '3 months'), 2) as previous_avg
    FROM monthly_totals
    GROUP BY category
)
SELECT
    cs.category,
    cs.months_active,
    cs.total_all_time,
    cs.avg_monthly_spend,
    cs.monthly_stddev,
    rt.recent_avg,
    rt.previous_avg,
    CASE
        WHEN rt.previous_avg IS NULL OR rt.previous_avg = 0 THEN NULL
        ELSE ROUND(((rt.recent_avg - rt.previous_avg) / rt.previous_avg * 100), 1)
    END as velocity_pct,
    CASE
        WHEN rt.recent_avg IS NULL OR rt.previous_avg IS NULL THEN 'insufficient_data'
        WHEN rt.recent_avg > rt.previous_avg * 1.2 THEN 'increasing'
        WHEN rt.recent_avg < rt.previous_avg * 0.8 THEN 'decreasing'
        ELSE 'stable'
    END as trend,
    cs.first_month,
    cs.last_month
FROM category_stats cs
LEFT JOIN recent_trend rt ON cs.category = rt.category
ORDER BY cs.total_all_time DESC;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_category_velocity_pk
    ON finance.mv_category_velocity(category);

COMMENT ON MATERIALIZED VIEW finance.mv_category_velocity IS
'Category spending velocity and trend analysis';


-- ============================================================================
-- 3. INCOME STABILITY
-- ============================================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS finance.mv_income_stability AS
WITH monthly_income AS (
    SELECT
        DATE_TRUNC('month', date)::DATE as month,
        SUM(amount) as income,
        COUNT(*) as income_count
    FROM finance.transactions
    WHERE amount > 0
    GROUP BY DATE_TRUNC('month', date)::DATE
),
stats AS (
    SELECT
        COUNT(*) as months_with_income,
        ROUND(AVG(income), 2) as avg_monthly_income,
        ROUND(STDDEV(income), 2) as income_stddev,
        MIN(income) as min_monthly_income,
        MAX(income) as max_monthly_income,
        MIN(month) as first_income_month,
        MAX(month) as last_income_month
    FROM monthly_income
)
SELECT
    s.*,
    -- Coefficient of variation (lower = more stable)
    CASE
        WHEN s.avg_monthly_income > 0 THEN ROUND((s.income_stddev / s.avg_monthly_income * 100), 1)
        ELSE NULL
    END as cv_pct,
    -- Stability rating
    CASE
        WHEN s.months_with_income < 3 THEN 'insufficient_data'
        WHEN s.income_stddev / NULLIF(s.avg_monthly_income, 0) < 0.1 THEN 'very_stable'
        WHEN s.income_stddev / NULLIF(s.avg_monthly_income, 0) < 0.25 THEN 'stable'
        WHEN s.income_stddev / NULLIF(s.avg_monthly_income, 0) < 0.5 THEN 'variable'
        ELSE 'unstable'
    END as stability_rating,
    -- Current month income
    (SELECT COALESCE(SUM(amount), 0) FROM finance.transactions
     WHERE amount > 0 AND DATE_TRUNC('month', date) = DATE_TRUNC('month', CURRENT_DATE)) as current_month_income
FROM stats s;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_income_stability_pk
    ON finance.mv_income_stability(first_income_month);

COMMENT ON MATERIALIZED VIEW finance.mv_income_stability IS
'Income stability metrics across all months';


-- ============================================================================
-- 4. ANOMALY DETECTION (vs Personal Baseline)
-- ============================================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS finance.mv_spending_anomalies AS
WITH category_baselines AS (
    -- Personal baseline: average and stddev per category
    SELECT
        category,
        ROUND(AVG(ABS(amount)), 2) as baseline_avg,
        ROUND(STDDEV(ABS(amount)), 2) as baseline_stddev,
        COUNT(*) as baseline_count
    FROM finance.transactions
    WHERE amount < 0
      AND date < DATE_TRUNC('month', CURRENT_DATE)  -- Exclude current month from baseline
    GROUP BY category
    HAVING COUNT(*) >= 3  -- Need at least 3 transactions for baseline
),
recent_transactions AS (
    SELECT
        t.id,
        t.date,
        t.merchant_name,
        t.category,
        ABS(t.amount) as amount,
        cb.baseline_avg,
        cb.baseline_stddev,
        cb.baseline_count
    FROM finance.transactions t
    JOIN category_baselines cb ON t.category = cb.category
    WHERE t.amount < 0
      AND t.date >= CURRENT_DATE - INTERVAL '30 days'
)
SELECT
    id as transaction_id,
    date,
    merchant_name,
    category,
    amount,
    baseline_avg,
    baseline_stddev,
    -- Z-score: how many standard deviations from mean
    CASE
        WHEN baseline_stddev > 0 THEN ROUND((amount - baseline_avg) / baseline_stddev, 2)
        ELSE 0
    END as z_score,
    -- Anomaly classification
    CASE
        WHEN baseline_stddev = 0 OR baseline_stddev IS NULL THEN 'no_baseline'
        WHEN (amount - baseline_avg) / baseline_stddev > 3 THEN 'severe_anomaly'
        WHEN (amount - baseline_avg) / baseline_stddev > 2 THEN 'anomaly'
        WHEN (amount - baseline_avg) / baseline_stddev > 1.5 THEN 'elevated'
        ELSE 'normal'
    END as anomaly_level,
    -- Percentage above baseline
    CASE
        WHEN baseline_avg > 0 THEN ROUND(((amount - baseline_avg) / baseline_avg * 100), 1)
        ELSE NULL
    END as pct_above_baseline
FROM recent_transactions
WHERE baseline_stddev > 0 AND (amount - baseline_avg) / baseline_stddev > 1.5  -- Only show elevated+
ORDER BY z_score DESC;

CREATE INDEX IF NOT EXISTS idx_mv_spending_anomalies_date
    ON finance.mv_spending_anomalies(date DESC);

COMMENT ON MATERIALIZED VIEW finance.mv_spending_anomalies IS
'Spending anomalies in last 30 days vs personal baseline (z-score > 1.5)';


-- ============================================================================
-- 5. DASHBOARD SUMMARY VIEW (Read-only for DashboardV2)
-- ============================================================================

CREATE OR REPLACE VIEW finance.v_dashboard_finance_summary AS
WITH current_month AS (
    SELECT
        SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END) as total_spend,
        SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) as total_income,
        COUNT(*) FILTER (WHERE amount < 0) as expense_count,
        COUNT(*) FILTER (WHERE amount > 0) as income_count
    FROM finance.transactions
    WHERE DATE_TRUNC('month', date) = DATE_TRUNC('month', CURRENT_DATE)
),
top_categories AS (
    SELECT
        category,
        SUM(ABS(amount)) as spend,
        COUNT(*) as count
    FROM finance.transactions
    WHERE amount < 0
      AND DATE_TRUNC('month', date) = DATE_TRUNC('month', CURRENT_DATE)
    GROUP BY category
    ORDER BY spend DESC
    LIMIT 5
),
anomaly_summary AS (
    SELECT
        COUNT(*) FILTER (WHERE anomaly_level = 'severe_anomaly') as severe_count,
        COUNT(*) FILTER (WHERE anomaly_level = 'anomaly') as anomaly_count,
        COUNT(*) FILTER (WHERE anomaly_level = 'elevated') as elevated_count
    FROM finance.mv_spending_anomalies
    WHERE date >= DATE_TRUNC('month', CURRENT_DATE)
)
SELECT
    -- Current month overview
    cm.total_spend as month_spend,
    cm.total_income as month_income,
    cm.expense_count,
    cm.income_count,
    cm.total_income - cm.total_spend as month_net,

    -- Top categories (as JSON array)
    (SELECT jsonb_agg(jsonb_build_object('category', category, 'spend', spend, 'count', count))
     FROM top_categories) as top_categories,

    -- Income stability
    (SELECT stability_rating FROM finance.mv_income_stability LIMIT 1) as income_stability,
    (SELECT cv_pct FROM finance.mv_income_stability LIMIT 1) as income_cv_pct,

    -- Anomalies this month
    ans.severe_count as anomalies_severe,
    ans.anomaly_count as anomalies_moderate,
    ans.elevated_count as anomalies_elevated,

    -- Health indicator
    CASE
        WHEN ans.severe_count > 0 THEN 'warning'
        WHEN ans.anomaly_count > 2 THEN 'caution'
        WHEN cm.total_spend > cm.total_income AND cm.total_income > 0 THEN 'overspend'
        ELSE 'healthy'
    END as health_status,

    -- Metadata
    CURRENT_TIMESTAMP as generated_at
FROM current_month cm
CROSS JOIN anomaly_summary ans;

COMMENT ON VIEW finance.v_dashboard_finance_summary IS
'Read-only summary for DashboardV2 consumption';


-- ============================================================================
-- 6. REFRESH FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION finance.refresh_financial_truth()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY finance.mv_monthly_spend;
    REFRESH MATERIALIZED VIEW CONCURRENTLY finance.mv_category_velocity;
    REFRESH MATERIALIZED VIEW finance.mv_income_stability;  -- No unique index, can't be concurrent
    REFRESH MATERIALIZED VIEW finance.mv_spending_anomalies;  -- No unique index, can't be concurrent
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION finance.refresh_financial_truth() IS
'Refresh all financial materialized views - run nightly or after bulk imports';
