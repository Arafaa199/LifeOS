-- Migration 022: Refund Tracking View
-- Purpose: Track refunds separately from spending (recommended by auditor)
-- Created: 2026-01-23

-- ============================================================================
-- 1. Refunds View (positive amounts that are NOT income/salary/deposit)
-- ============================================================================
CREATE OR REPLACE VIEW finance.v_refunds AS
SELECT
    id,
    date,
    transaction_at,
    merchant_name,
    merchant_name_clean,
    category,
    amount,  -- Positive = money returned
    currency,
    notes,
    client_id,
    created_at
FROM finance.transactions
WHERE amount > 0
  AND category NOT IN ('Income', 'Salary', 'Deposit')
  AND is_hidden = false
  AND is_quarantined = false
ORDER BY date DESC;

COMMENT ON VIEW finance.v_refunds IS 'Refunds: positive non-income transactions (returns, reversals, cashback)';

-- ============================================================================
-- 2. Monthly Refund Summary
-- ============================================================================
CREATE OR REPLACE VIEW finance.v_monthly_refunds AS
SELECT
    date_trunc('month', transaction_at AT TIME ZONE 'Asia/Dubai')::date AS month,
    currency,
    category,
    COUNT(*) AS refund_count,
    SUM(amount) AS total_refunded,
    AVG(amount) AS avg_refund
FROM finance.transactions
WHERE amount > 0
  AND category NOT IN ('Income', 'Salary', 'Deposit')
  AND is_hidden = false
  AND is_quarantined = false
GROUP BY 1, 2, 3
ORDER BY month DESC, total_refunded DESC;

COMMENT ON VIEW finance.v_monthly_refunds IS 'Monthly refund totals by category';

-- ============================================================================
-- 3. Net Spend View (expenses minus refunds for true spend)
-- ============================================================================
CREATE OR REPLACE VIEW finance.v_net_monthly_spend AS
WITH gross_spend AS (
    SELECT
        date_trunc('month', transaction_at AT TIME ZONE 'Asia/Dubai')::date AS month,
        currency,
        category,
        SUM(ABS(amount)) AS gross_spent
    FROM finance.transactions
    WHERE amount < 0
      AND category NOT IN ('Transfer', 'Income', 'Salary', 'Deposit')
      AND is_hidden = false
      AND is_quarantined = false
    GROUP BY 1, 2, 3
),
refunds AS (
    SELECT
        date_trunc('month', transaction_at AT TIME ZONE 'Asia/Dubai')::date AS month,
        currency,
        category,
        SUM(amount) AS total_refunded
    FROM finance.transactions
    WHERE amount > 0
      AND category NOT IN ('Income', 'Salary', 'Deposit')
      AND is_hidden = false
      AND is_quarantined = false
    GROUP BY 1, 2, 3
)
SELECT
    COALESCE(g.month, r.month) AS month,
    COALESCE(g.currency, r.currency) AS currency,
    COALESCE(g.category, r.category) AS category,
    COALESCE(g.gross_spent, 0) AS gross_spent,
    COALESCE(r.total_refunded, 0) AS refunds,
    COALESCE(g.gross_spent, 0) - COALESCE(r.total_refunded, 0) AS net_spent
FROM gross_spend g
FULL OUTER JOIN refunds r
    ON g.month = r.month
    AND g.currency = r.currency
    AND g.category = r.category
ORDER BY month DESC, net_spent DESC;

COMMENT ON VIEW finance.v_net_monthly_spend IS 'Net monthly spend = gross expenses minus refunds';

-- ============================================================================
-- 4. Integrate refunds into anomaly detection
-- ============================================================================
-- Add refund anomalies (unusually large refunds could indicate fraud/issues)
CREATE OR REPLACE VIEW finance.v_refund_anomalies AS
WITH refund_stats AS (
    SELECT
        category,
        currency,
        AVG(amount) AS avg_refund,
        STDDEV(amount) AS stddev_refund,
        COUNT(*) AS sample_size
    FROM finance.transactions
    WHERE amount > 0
      AND category NOT IN ('Income', 'Salary', 'Deposit')
      AND is_hidden = false
      AND is_quarantined = false
    GROUP BY category, currency
    HAVING COUNT(*) >= 2  -- Need at least 2 samples
)
SELECT
    t.id,
    t.date,
    t.merchant_name,
    t.category,
    t.currency,
    t.amount,
    s.avg_refund AS category_avg,
    s.stddev_refund AS category_stddev,
    CASE
        WHEN s.stddev_refund = 0 OR s.stddev_refund IS NULL THEN 0
        ELSE ROUND((t.amount - s.avg_refund) / s.stddev_refund, 2)
    END AS z_score,
    CASE
        WHEN s.stddev_refund IS NULL OR s.stddev_refund = 0 THEN 'insufficient_data'
        WHEN (t.amount - s.avg_refund) / s.stddev_refund > 2 THEN 'large_refund'
        WHEN (t.amount - s.avg_refund) / s.stddev_refund < -2 THEN 'small_refund'
        ELSE 'normal'
    END AS anomaly_status
FROM finance.transactions t
LEFT JOIN refund_stats s ON t.category = s.category AND t.currency = s.currency
WHERE t.amount > 0
  AND t.category NOT IN ('Income', 'Salary', 'Deposit')
  AND t.is_hidden = false
  AND t.is_quarantined = false
ORDER BY z_score DESC NULLS LAST;

COMMENT ON VIEW finance.v_refund_anomalies IS 'Refund anomaly detection - unusually large/small refunds';

-- ============================================================================
-- Grant read access
-- ============================================================================
GRANT SELECT ON finance.v_refunds TO nexus;
GRANT SELECT ON finance.v_monthly_refunds TO nexus;
GRANT SELECT ON finance.v_net_monthly_spend TO nexus;
GRANT SELECT ON finance.v_refund_anomalies TO nexus;
