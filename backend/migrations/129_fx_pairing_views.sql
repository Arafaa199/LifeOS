-- Migration 129 (part 2): Patch views to exclude fx_metadata rows from financial aggregations

-- 1. normalized.v_daily_finance — add fx_metadata exclusion
CREATE OR REPLACE VIEW normalized.v_daily_finance AS
WITH daily_category AS (
    SELECT
        finance.to_business_date(transaction_at) AS date,
        COALESCE(category, 'Uncategorized'::varchar) AS category,
        SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END) AS cat_spend,
        SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) AS cat_income,
        COUNT(*) AS cat_count
    FROM finance.transactions
    WHERE is_quarantined IS NOT TRUE
      AND pairing_role IS DISTINCT FROM 'fx_metadata'
    GROUP BY finance.to_business_date(transaction_at), COALESCE(category, 'Uncategorized'::varchar)
)
SELECT
    date,
    COALESCE(SUM(cat_spend), 0) AS spend_total,
    COALESCE(SUM(cat_income), 0) AS income_total,
    SUM(cat_count)::integer AS transaction_count,
    COALESCE(SUM(CASE WHEN category = 'Groceries' THEN cat_spend END), 0) AS spend_groceries,
    COALESCE(SUM(CASE WHEN category IN ('Dining', 'Restaurants', 'Food Delivery') THEN cat_spend END), 0) AS spend_restaurants,
    COALESCE(SUM(CASE WHEN category = 'Transport' THEN cat_spend END), 0) AS spend_transport,
    jsonb_object_agg(category, cat_spend) FILTER (WHERE cat_spend > 0) AS spending_by_category
FROM daily_category
GROUP BY date;

-- 2. finance.v_dashboard_finance_summary — add fx_metadata exclusion
CREATE OR REPLACE VIEW finance.v_dashboard_finance_summary AS
WITH current_month AS (
    SELECT
        SUM(CASE WHEN COALESCE(amount_preferred, amount) < 0 THEN ABS(COALESCE(amount_preferred, amount)) ELSE 0 END) AS total_spend,
        SUM(CASE WHEN COALESCE(amount_preferred, amount) > 0 THEN COALESCE(amount_preferred, amount) ELSE 0 END) AS total_income,
        COUNT(*) FILTER (WHERE amount < 0) AS expense_count,
        COUNT(*) FILTER (WHERE amount > 0) AS income_count
    FROM finance.transactions
    WHERE date_trunc('month', date::timestamptz) = date_trunc('month', CURRENT_DATE::timestamptz)
      AND pairing_role IS DISTINCT FROM 'fx_metadata'
), top_categories AS (
    SELECT category,
        SUM(ABS(COALESCE(amount_preferred, amount))) AS spend,
        COUNT(*) AS count
    FROM finance.transactions
    WHERE amount < 0
      AND date_trunc('month', date::timestamptz) = date_trunc('month', CURRENT_DATE::timestamptz)
      AND pairing_role IS DISTINCT FROM 'fx_metadata'
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

-- 3. finance.v_sms_ingestion_health — add paired_count column
CREATE OR REPLACE VIEW finance.v_sms_ingestion_health AS
SELECT
    raw_data->>'sender' AS sender,
    COUNT(*) AS total_messages,
    COUNT(*) FILTER (WHERE amount IS NOT NULL) AS created_tx,
    COUNT(*) FILTER (WHERE pairing_role = 'fx_metadata') AS paired_count,
    ROUND(AVG((raw_data->>'confidence')::numeric), 2) AS avg_confidence,
    MIN(transaction_at) AS first_message,
    MAX(transaction_at) AS last_message,
    COUNT(*) FILTER (WHERE transaction_at >= CURRENT_DATE - INTERVAL '7 days') AS last_7d_count
FROM finance.transactions
WHERE source = 'sms' AND transaction_at >= CURRENT_DATE - INTERVAL '60 days'
GROUP BY raw_data->>'sender'
ORDER BY COUNT(*) DESC;

-- 4. Recreate mv_monthly_spend with fx_metadata exclusion
DROP MATERIALIZED VIEW IF EXISTS finance.mv_monthly_spend CASCADE;
CREATE MATERIALIZED VIEW finance.mv_monthly_spend AS
SELECT
    (date_trunc('month', date::timestamptz))::date AS month,
    category,
    COUNT(*) AS transaction_count,
    SUM(ABS(COALESCE(amount_preferred, amount))) AS total_spend,
    ROUND(AVG(ABS(COALESCE(amount_preferred, amount))), 2) AS avg_transaction,
    MIN(ABS(COALESCE(amount_preferred, amount))) AS min_transaction,
    MAX(ABS(COALESCE(amount_preferred, amount))) AS max_transaction,
    ROUND(STDDEV(ABS(COALESCE(amount_preferred, amount))), 2) AS stddev_amount
FROM finance.transactions
WHERE amount < 0
  AND pairing_role IS DISTINCT FROM 'fx_metadata'
GROUP BY (date_trunc('month', date::timestamptz))::date, category
ORDER BY (date_trunc('month', date::timestamptz))::date DESC, SUM(ABS(COALESCE(amount_preferred, amount))) DESC;

-- 5. Recreate mv_spending_anomalies with fx_metadata exclusion
DROP MATERIALIZED VIEW IF EXISTS finance.mv_spending_anomalies CASCADE;
CREATE MATERIALIZED VIEW finance.mv_spending_anomalies AS
WITH category_baselines AS (
    SELECT category,
        ROUND(AVG(ABS(COALESCE(amount_preferred, amount))), 2) AS baseline_avg,
        ROUND(STDDEV(ABS(COALESCE(amount_preferred, amount))), 2) AS baseline_stddev,
        COUNT(*) AS baseline_count
    FROM finance.transactions
    WHERE amount < 0
      AND date < date_trunc('month', CURRENT_DATE::timestamptz)
      AND pairing_role IS DISTINCT FROM 'fx_metadata'
    GROUP BY category
    HAVING COUNT(*) >= 3
), recent_transactions AS (
    SELECT t.id, t.date, t.merchant_name, t.category,
        ABS(COALESCE(t.amount_preferred, t.amount)) AS amount,
        cb.baseline_avg, cb.baseline_stddev, cb.baseline_count
    FROM finance.transactions t
    JOIN category_baselines cb ON t.category = cb.category
    WHERE t.amount < 0
      AND t.date >= CURRENT_DATE - INTERVAL '30 days'
      AND t.pairing_role IS DISTINCT FROM 'fx_metadata'
)
SELECT id AS transaction_id, date, merchant_name, category, amount,
    baseline_avg, baseline_stddev,
    CASE
        WHEN baseline_stddev > 0 THEN ROUND((amount - baseline_avg) / baseline_stddev, 2)
        ELSE 0
    END AS z_score,
    CASE
        WHEN baseline_stddev = 0 OR baseline_stddev IS NULL THEN 'no_baseline'
        WHEN (amount - baseline_avg) / baseline_stddev > 3 THEN 'severe_anomaly'
        WHEN (amount - baseline_avg) / baseline_stddev > 2 THEN 'anomaly'
        WHEN (amount - baseline_avg) / baseline_stddev > 1.5 THEN 'elevated'
        ELSE 'normal'
    END AS anomaly_level
FROM recent_transactions;

-- 6. Recreate mv_category_velocity with fx_metadata exclusion
DROP MATERIALIZED VIEW IF EXISTS finance.mv_category_velocity CASCADE;
CREATE MATERIALIZED VIEW finance.mv_category_velocity AS
WITH monthly_totals AS (
    SELECT category,
        (date_trunc('month', date::timestamptz))::date AS month,
        SUM(ABS(COALESCE(amount_preferred, amount))) AS spend
    FROM finance.transactions
    WHERE amount < 0
      AND pairing_role IS DISTINCT FROM 'fx_metadata'
    GROUP BY category, (date_trunc('month', date::timestamptz))::date
), category_stats AS (
    SELECT category,
        COUNT(DISTINCT month) AS months_active,
        SUM(spend) AS total_all_time,
        ROUND(AVG(spend), 2) AS avg_monthly_spend,
        ROUND(STDDEV(spend), 2) AS monthly_stddev,
        MIN(month) AS first_month,
        MAX(month) AS last_month
    FROM monthly_totals
    GROUP BY category
), recent_trend AS (
    SELECT category,
        ROUND(AVG(spend) FILTER (WHERE month >= date_trunc('month', CURRENT_DATE::timestamptz) - INTERVAL '3 months'), 2) AS recent_avg,
        ROUND(AVG(spend) FILTER (WHERE month >= date_trunc('month', CURRENT_DATE::timestamptz) - INTERVAL '6 months'
                                   AND month < date_trunc('month', CURRENT_DATE::timestamptz) - INTERVAL '3 months'), 2) AS previous_avg
    FROM monthly_totals
    GROUP BY category
)
SELECT cs.category, cs.months_active, cs.total_all_time, cs.avg_monthly_spend, cs.monthly_stddev,
    rt.recent_avg, rt.previous_avg,
    CASE
        WHEN rt.previous_avg IS NULL OR rt.previous_avg = 0 THEN NULL
        ELSE ROUND(((rt.recent_avg - rt.previous_avg) / rt.previous_avg) * 100, 1)
    END AS velocity_pct,
    CASE
        WHEN rt.recent_avg IS NULL OR rt.previous_avg IS NULL THEN 'insufficient_data'
        WHEN rt.recent_avg > rt.previous_avg * 1.2 THEN 'increasing'
        WHEN rt.recent_avg < rt.previous_avg * 0.8 THEN 'decreasing'
        ELSE 'stable'
    END AS trend,
    cs.first_month, cs.last_month
FROM category_stats cs
LEFT JOIN recent_trend rt ON cs.category = rt.category
ORDER BY cs.total_all_time DESC;

-- Refresh materialized views
REFRESH MATERIALIZED VIEW finance.mv_monthly_spend;
REFRESH MATERIALIZED VIEW finance.mv_spending_anomalies;
REFRESH MATERIALIZED VIEW finance.mv_category_velocity;
