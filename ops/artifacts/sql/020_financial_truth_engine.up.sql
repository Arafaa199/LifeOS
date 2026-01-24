-- Migration 020: Financial Truth Engine Views
-- Purpose: Deterministic, read-only financial insight views
-- Created: 2026-01-23

-- ============================================================================
-- 1. Monthly Spend View (normalized, excludes transfers/income)
-- ============================================================================
CREATE OR REPLACE VIEW finance.v_monthly_spend AS
SELECT
    date_trunc('month', transaction_at AT TIME ZONE 'Asia/Dubai')::date AS month,
    currency,
    category,
    COUNT(*) AS txn_count,
    SUM(ABS(amount)) AS total_spent,
    AVG(ABS(amount)) AS avg_per_txn,
    MIN(ABS(amount)) AS min_txn,
    MAX(ABS(amount)) AS max_txn
FROM finance.transactions
WHERE amount < 0  -- Only expenses
  AND category NOT IN ('Transfer', 'Income', 'Salary', 'Deposit')
  AND is_hidden = false
  AND is_quarantined = false
GROUP BY 1, 2, 3
ORDER BY month DESC, total_spent DESC;

COMMENT ON VIEW finance.v_monthly_spend IS 'Monthly spending by category, excludes transfers and income';

-- ============================================================================
-- 2. Category Velocity (spend rate per day/week/month)
-- ============================================================================
CREATE OR REPLACE VIEW finance.v_category_velocity AS
WITH date_range AS (
    SELECT
        MIN(date) AS first_date,
        MAX(date) AS last_date,
        GREATEST(1, (MAX(date) - MIN(date))::integer) AS days_span
    FROM finance.transactions
    WHERE amount < 0
      AND category NOT IN ('Transfer', 'Income', 'Salary', 'Deposit')
),
category_totals AS (
    SELECT
        category,
        currency,
        COUNT(*) AS txn_count,
        SUM(ABS(amount)) AS total_spent
    FROM finance.transactions
    WHERE amount < 0
      AND category NOT IN ('Transfer', 'Income', 'Salary', 'Deposit')
      AND is_hidden = false
      AND is_quarantined = false
    GROUP BY category, currency
)
SELECT
    ct.category,
    ct.currency,
    ct.txn_count,
    ct.total_spent,
    ROUND(ct.total_spent / dr.days_span, 2) AS spend_per_day,
    ROUND(ct.total_spent / (dr.days_span / 7.0), 2) AS spend_per_week,
    ROUND(ct.total_spent / (dr.days_span / 30.0), 2) AS spend_per_month,
    dr.first_date,
    dr.last_date,
    dr.days_span
FROM category_totals ct
CROSS JOIN date_range dr
ORDER BY spend_per_month DESC;

COMMENT ON VIEW finance.v_category_velocity IS 'Category spend velocity (daily/weekly/monthly rates)';

-- ============================================================================
-- 3. Income Stability (rolling avg + stddev)
-- ============================================================================
CREATE OR REPLACE VIEW finance.v_income_stability AS
WITH monthly_income AS (
    SELECT
        date_trunc('month', transaction_at AT TIME ZONE 'Asia/Dubai')::date AS month,
        currency,
        SUM(amount) AS total_income,
        COUNT(*) AS income_count
    FROM finance.transactions
    WHERE amount > 0
      AND category IN ('Income', 'Salary')
      AND is_hidden = false
      AND is_quarantined = false
    GROUP BY 1, 2
)
SELECT
    month,
    currency,
    total_income,
    income_count,
    AVG(total_income) OVER (
        PARTITION BY currency
        ORDER BY month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3mo_avg,
    STDDEV(total_income) OVER (
        PARTITION BY currency
        ORDER BY month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3mo_stddev,
    CASE
        WHEN STDDEV(total_income) OVER (
            PARTITION BY currency
            ORDER BY month
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) = 0 THEN 100.0
        ELSE ROUND(
            (1 - (STDDEV(total_income) OVER (
                PARTITION BY currency
                ORDER BY month
                ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
            ) / NULLIF(AVG(total_income) OVER (
                PARTITION BY currency
                ORDER BY month
                ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
            ), 0))) * 100, 1
        )
    END AS stability_score  -- Higher = more stable (100 = perfectly stable)
FROM monthly_income
ORDER BY currency, month DESC;

COMMENT ON VIEW finance.v_income_stability IS 'Income stability metrics with rolling averages and variance';

-- ============================================================================
-- 4. Anomaly Detection (vs personal baseline)
-- ============================================================================
CREATE OR REPLACE VIEW finance.v_anomaly_baseline AS
WITH category_stats AS (
    -- Calculate baseline stats per category (last 90 days)
    SELECT
        category,
        currency,
        AVG(ABS(amount)) AS avg_amount,
        STDDEV(ABS(amount)) AS stddev_amount,
        COUNT(*) AS sample_size
    FROM finance.transactions
    WHERE amount < 0
      AND category NOT IN ('Transfer', 'Income', 'Salary', 'Deposit')
      AND date >= CURRENT_DATE - INTERVAL '90 days'
      AND is_hidden = false
    GROUP BY category, currency
    HAVING COUNT(*) >= 3  -- Need at least 3 samples for meaningful stats
),
recent_txns AS (
    -- Recent transactions (last 30 days)
    SELECT
        t.id,
        t.date,
        t.merchant_name,
        t.category,
        t.currency,
        ABS(t.amount) AS amount,
        t.transaction_at
    FROM finance.transactions t
    WHERE t.amount < 0
      AND t.date >= CURRENT_DATE - INTERVAL '30 days'
      AND t.is_hidden = false
      AND t.is_quarantined = false
)
SELECT
    r.id,
    r.date,
    r.merchant_name,
    r.category,
    r.currency,
    r.amount,
    s.avg_amount AS category_avg,
    s.stddev_amount AS category_stddev,
    CASE
        WHEN s.stddev_amount = 0 OR s.stddev_amount IS NULL THEN 0
        ELSE ROUND((r.amount - s.avg_amount) / s.stddev_amount, 2)
    END AS z_score,
    CASE
        WHEN s.stddev_amount IS NULL OR s.stddev_amount = 0 THEN 'insufficient_data'
        WHEN (r.amount - s.avg_amount) / s.stddev_amount > 2 THEN 'high_anomaly'
        WHEN (r.amount - s.avg_amount) / s.stddev_amount > 1 THEN 'mild_anomaly'
        WHEN (r.amount - s.avg_amount) / s.stddev_amount < -1 THEN 'unusually_low'
        ELSE 'normal'
    END AS anomaly_status
FROM recent_txns r
LEFT JOIN category_stats s ON r.category = s.category AND r.currency = s.currency
ORDER BY z_score DESC NULLS LAST;

COMMENT ON VIEW finance.v_anomaly_baseline IS 'Transaction anomaly detection using z-scores against category baseline';

-- ============================================================================
-- 5. Financial Summary (for DashboardV2)
-- ============================================================================
CREATE OR REPLACE VIEW finance.v_financial_truth_summary AS
WITH current_month AS (
    SELECT date_trunc('month', CURRENT_DATE)::date AS month_start
),
month_stats AS (
    SELECT
        SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END) AS total_spent,
        SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) AS total_income,
        COUNT(CASE WHEN amount < 0 THEN 1 END) AS expense_count,
        COUNT(CASE WHEN amount > 0 THEN 1 END) AS income_count
    FROM finance.transactions t, current_month cm
    WHERE date_trunc('month', t.transaction_at AT TIME ZONE 'Asia/Dubai')::date = cm.month_start
      AND t.is_hidden = false
      AND t.is_quarantined = false
      AND t.category NOT IN ('Transfer')
),
top_categories AS (
    SELECT
        category,
        SUM(ABS(amount)) AS spent
    FROM finance.transactions t, current_month cm
    WHERE date_trunc('month', t.transaction_at AT TIME ZONE 'Asia/Dubai')::date = cm.month_start
      AND t.amount < 0
      AND t.category NOT IN ('Transfer', 'Income', 'Salary')
      AND t.is_hidden = false
    GROUP BY category
    ORDER BY spent DESC
    LIMIT 3
),
anomalies AS (
    SELECT COUNT(*) AS anomaly_count
    FROM finance.v_anomaly_baseline
    WHERE anomaly_status = 'high_anomaly'
      AND date >= date_trunc('month', CURRENT_DATE)::date
),
income_trend AS (
    SELECT
        stability_score,
        rolling_3mo_avg
    FROM finance.v_income_stability
    WHERE currency = 'AED'
    ORDER BY month DESC
    LIMIT 1
)
SELECT
    cm.month_start AS report_month,
    ms.total_spent,
    ms.total_income,
    ms.total_income - ms.total_spent AS net_savings,
    CASE
        WHEN ms.total_income > 0
        THEN ROUND((ms.total_income - ms.total_spent) / ms.total_income * 100, 1)
        ELSE 0
    END AS savings_rate_pct,
    ms.expense_count,
    ms.income_count,
    (SELECT json_agg(json_build_object('category', category, 'spent', spent)) FROM top_categories) AS top_spend_categories,
    a.anomaly_count,
    it.stability_score AS income_stability,
    it.rolling_3mo_avg AS avg_monthly_income,
    CURRENT_TIMESTAMP AS generated_at
FROM current_month cm
CROSS JOIN month_stats ms
CROSS JOIN anomalies a
LEFT JOIN income_trend it ON true;

COMMENT ON VIEW finance.v_financial_truth_summary IS 'Unified financial summary for DashboardV2 consumption';

-- ============================================================================
-- Grant read access
-- ============================================================================
GRANT SELECT ON finance.v_monthly_spend TO nexus;
GRANT SELECT ON finance.v_category_velocity TO nexus;
GRANT SELECT ON finance.v_income_stability TO nexus;
GRANT SELECT ON finance.v_anomaly_baseline TO nexus;
GRANT SELECT ON finance.v_financial_truth_summary TO nexus;
