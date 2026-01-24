-- Migration 051: Reconciliation Views for Data Trust
-- Purpose: Validate financial data completeness and accuracy
-- Created: 2026-01-24
-- Updated: Uses raw.sms_classifications (not raw.bank_sms)

-- =============================================================================
-- 1. SMS INGESTION HEALTH
-- Track SMS classification success rate by sender
-- =============================================================================

CREATE OR REPLACE VIEW finance.v_sms_ingestion_health AS
SELECT
    sender,
    COUNT(*) AS total_messages,
    COUNT(*) FILTER (WHERE created_transaction = true) AS created_tx,
    COUNT(*) FILTER (WHERE canonical_intent = 'IGNORE') AS ignored,
    ROUND(AVG(confidence)::numeric, 2) AS avg_confidence,
    MIN(received_at) AS first_message,
    MAX(received_at) AS last_message,
    COUNT(*) FILTER (WHERE received_at >= CURRENT_DATE - INTERVAL '7 days') AS last_7d_count
FROM raw.sms_classifications
WHERE received_at >= CURRENT_DATE - INTERVAL '60 days'
GROUP BY sender
ORDER BY total_messages DESC;

COMMENT ON VIEW finance.v_sms_ingestion_health IS
'SMS classification health by sender over the last 60 days';

-- =============================================================================
-- 2. DAILY SPEND RECONCILIATION
-- Compare SMS received vs transactions created per day
-- =============================================================================

CREATE OR REPLACE VIEW finance.v_daily_spend_reconciliation AS
WITH daily_sms AS (
    SELECT
        date_trunc('day', received_at AT TIME ZONE 'Asia/Dubai')::date AS day,
        COUNT(*) AS sms_count,
        COUNT(*) FILTER (WHERE canonical_intent LIKE 'FIN_TXN%') AS financial_sms,
        COUNT(*) FILTER (WHERE created_transaction = true) AS sms_created_tx
    FROM raw.sms_classifications
    WHERE received_at >= CURRENT_DATE - INTERVAL '60 days'
    GROUP BY 1
),
daily_tx AS (
    SELECT
        (transaction_at AT TIME ZONE 'Asia/Dubai')::date AS day,
        COUNT(*) AS tx_count,
        SUM(amount) FILTER (WHERE amount < 0) AS spend_total,
        SUM(amount) FILTER (WHERE amount > 0) AS income_total,
        COUNT(*) FILTER (WHERE external_id LIKE 'sms:%') AS sms_sourced
    FROM finance.transactions
    WHERE transaction_at >= CURRENT_DATE - INTERVAL '60 days'
      AND NOT is_hidden AND NOT is_quarantined
    GROUP BY 1
)
SELECT
    COALESCE(s.day, t.day) AS day,
    COALESCE(s.sms_count, 0) AS sms_received,
    COALESCE(s.financial_sms, 0) AS sms_financial,
    COALESCE(s.sms_created_tx, 0) AS sms_created_tx,
    COALESCE(t.tx_count, 0) AS transactions_total,
    COALESCE(t.sms_sourced, 0) AS tx_from_sms,
    ABS(COALESCE(t.spend_total, 0)) AS spend_aed,
    COALESCE(t.income_total, 0) AS income_aed,
    CASE
        WHEN COALESCE(s.financial_sms, 0) > COALESCE(t.sms_sourced, 0)
        THEN 'SMS_NOT_CAPTURED'
        ELSE 'OK'
    END AS status
FROM daily_sms s
FULL OUTER JOIN daily_tx t ON s.day = t.day
ORDER BY day DESC;

COMMENT ON VIEW finance.v_daily_spend_reconciliation IS
'Daily reconciliation: SMS received vs transactions created';

-- =============================================================================
-- 3. DATA COVERAGE GAPS
-- Flag days where we might be missing financial data
-- =============================================================================

CREATE OR REPLACE VIEW finance.v_data_coverage_gaps AS
WITH date_series AS (
    SELECT generate_series(
        CURRENT_DATE - INTERVAL '60 days',
        CURRENT_DATE,
        INTERVAL '1 day'
    )::date AS day
),
daily_stats AS (
    SELECT
        (transaction_at AT TIME ZONE 'Asia/Dubai')::date AS day,
        COUNT(*) AS tx_count,
        SUM(CASE WHEN amount < 0 THEN 1 ELSE 0 END) AS expense_count,
        SUM(CASE WHEN amount > 0 THEN 1 ELSE 0 END) AS income_count,
        ABS(SUM(CASE WHEN amount < 0 THEN amount ELSE 0 END)) AS total_spend
    FROM finance.transactions
    WHERE transaction_at >= CURRENT_DATE - INTERVAL '60 days'
      AND NOT is_hidden
      AND NOT is_quarantined
    GROUP BY 1
),
averages AS (
    SELECT
        AVG(tx_count) AS avg_tx_count,
        AVG(expense_count) AS avg_expense_count,
        AVG(total_spend) AS avg_spend,
        STDDEV(tx_count) AS stddev_tx_count,
        STDDEV(total_spend) AS stddev_spend
    FROM daily_stats
    WHERE tx_count > 0
)
SELECT
    d.day,
    EXTRACT(DOW FROM d.day) AS day_of_week,
    TO_CHAR(d.day, 'Day') AS day_name,
    COALESCE(s.tx_count, 0) AS tx_count,
    COALESCE(s.expense_count, 0) AS expense_count,
    COALESCE(s.income_count, 0) AS income_count,
    COALESCE(s.total_spend, 0) AS total_spend,
    ROUND(a.avg_tx_count, 1) AS avg_tx_count,
    ROUND(a.avg_spend, 2) AS avg_spend,
    CASE
        WHEN s.tx_count IS NULL OR s.tx_count = 0
        THEN 'NO_TRANSACTIONS'
        WHEN s.tx_count < (a.avg_tx_count - 2 * a.stddev_tx_count)
        THEN 'UNUSUALLY_LOW_COUNT'
        WHEN s.total_spend > (a.avg_spend + 2 * a.stddev_spend)
        THEN 'UNUSUALLY_HIGH_SPEND'
        ELSE 'OK'
    END AS status,
    CASE
        WHEN a.stddev_spend > 0
        THEN ROUND((COALESCE(s.total_spend, 0) - a.avg_spend) / a.stddev_spend, 2)
        ELSE 0
    END AS spend_z_score
FROM date_series d
CROSS JOIN averages a
LEFT JOIN daily_stats s ON d.day = s.day
ORDER BY d.day DESC;

COMMENT ON VIEW finance.v_data_coverage_gaps IS
'Identify days with missing or anomalous transaction data based on historical patterns';

-- =============================================================================
-- 4. RECEIPT TO TRANSACTION MATCHING
-- Identify receipts that need linking and potential matches
-- =============================================================================

CREATE OR REPLACE VIEW finance.v_receipt_transaction_matching AS
WITH unlinked_receipts AS (
    SELECT
        r.id AS receipt_id,
        r.vendor,
        r.store_name,
        r.receipt_date,
        r.total_amount,
        r.currency,
        r.parse_status,
        r.created_at
    FROM finance.receipts r
    WHERE r.linked_transaction_id IS NULL
      AND r.parse_status = 'parsed'
      AND r.total_amount IS NOT NULL
      AND r.receipt_date >= CURRENT_DATE - INTERVAL '30 days'
),
potential_matches AS (
    SELECT
        ur.receipt_id,
        t.id AS transaction_id,
        t.merchant_name,
        t.amount,
        (t.transaction_at AT TIME ZONE 'Asia/Dubai')::date AS tx_date,
        CASE
            WHEN ur.receipt_date = (t.transaction_at AT TIME ZONE 'Asia/Dubai')::date
                 AND ABS(ABS(t.amount) - ur.total_amount) < 0.01
            THEN 100
            WHEN ur.receipt_date = (t.transaction_at AT TIME ZONE 'Asia/Dubai')::date
                 AND ABS(ABS(t.amount) - ur.total_amount) / ur.total_amount < 0.05
            THEN 80
            WHEN ABS(ur.receipt_date - (t.transaction_at AT TIME ZONE 'Asia/Dubai')::date) <= 1
                 AND ABS(ABS(t.amount) - ur.total_amount) < 0.01
            THEN 70
            WHEN ur.receipt_date = (t.transaction_at AT TIME ZONE 'Asia/Dubai')::date
            THEN 50
            ELSE 0
        END AS match_score
    FROM unlinked_receipts ur
    CROSS JOIN LATERAL (
        SELECT *
        FROM finance.transactions t
        WHERE NOT t.is_hidden
          AND NOT t.is_quarantined
          AND t.amount < 0
          AND t.receipt_processed = false
          AND ABS((t.transaction_at AT TIME ZONE 'Asia/Dubai')::date - ur.receipt_date) <= 3
    ) t
)
SELECT
    ur.receipt_id,
    ur.vendor,
    ur.store_name,
    ur.receipt_date,
    ur.total_amount AS receipt_amount,
    ur.currency,
    pm.transaction_id,
    pm.merchant_name AS tx_merchant,
    ABS(pm.amount) AS tx_amount,
    pm.tx_date,
    pm.match_score,
    CASE
        WHEN pm.match_score >= 70 THEN 'HIGH_CONFIDENCE'
        WHEN pm.match_score >= 50 THEN 'MEDIUM_CONFIDENCE'
        WHEN pm.match_score > 0 THEN 'LOW_CONFIDENCE'
        ELSE 'NO_MATCH'
    END AS match_quality
FROM unlinked_receipts ur
LEFT JOIN potential_matches pm ON ur.receipt_id = pm.receipt_id AND pm.match_score > 0
ORDER BY ur.receipt_date DESC, pm.match_score DESC NULLS LAST;

COMMENT ON VIEW finance.v_receipt_transaction_matching IS
'Identify unlinked receipts and their potential transaction matches with confidence scoring';

-- =============================================================================
-- 5. RECONCILIATION SUMMARY (Executive Dashboard)
-- =============================================================================

CREATE OR REPLACE VIEW finance.v_reconciliation_summary AS
WITH sms_stats AS (
    SELECT
        COUNT(*) AS total_sms,
        COUNT(*) FILTER (WHERE canonical_intent LIKE 'FIN_TXN%') AS financial_sms,
        COUNT(*) FILTER (WHERE created_transaction = true) AS sms_created_tx,
        ROUND(100.0 * COUNT(*) FILTER (WHERE created_transaction = true) /
              NULLIF(COUNT(*) FILTER (WHERE canonical_intent LIKE 'FIN_TXN%'), 0), 1) AS capture_rate
    FROM raw.sms_classifications
    WHERE received_at >= CURRENT_DATE - INTERVAL '60 days'
),
tx_stats AS (
    SELECT
        COUNT(*) AS total_transactions,
        COUNT(*) FILTER (WHERE external_id LIKE 'sms:%') AS sms_sourced,
        ABS(SUM(amount) FILTER (WHERE amount < 0)) AS total_spend,
        SUM(amount) FILTER (WHERE amount > 0) AS total_income
    FROM finance.transactions
    WHERE transaction_at >= CURRENT_DATE - INTERVAL '60 days'
      AND NOT is_hidden AND NOT is_quarantined
),
receipt_stats AS (
    SELECT
        COUNT(*) AS total_receipts,
        COUNT(*) FILTER (WHERE parse_status = 'parsed') AS parsed_receipts,
        COUNT(*) FILTER (WHERE linked_transaction_id IS NOT NULL) AS linked_receipts
    FROM finance.receipts
    WHERE receipt_date >= CURRENT_DATE - INTERVAL '60 days'
),
gap_stats AS (
    SELECT
        COUNT(*) FILTER (WHERE status != 'OK') AS days_with_issues,
        COUNT(*) AS total_days
    FROM finance.v_data_coverage_gaps
)
SELECT
    s.total_sms,
    s.financial_sms,
    s.sms_created_tx,
    s.capture_rate AS sms_capture_rate,
    t.total_transactions,
    t.sms_sourced AS tx_from_sms,
    ROUND(t.total_spend, 2) AS total_spend_aed,
    ROUND(t.total_income, 2) AS total_income_aed,
    r.total_receipts,
    r.parsed_receipts,
    r.linked_receipts,
    g.days_with_issues,
    g.total_days,
    ROUND(100.0 * (g.total_days - g.days_with_issues) / NULLIF(g.total_days, 0), 1) AS coverage_score
FROM sms_stats s
CROSS JOIN tx_stats t
CROSS JOIN receipt_stats r
CROSS JOIN gap_stats g;

COMMENT ON VIEW finance.v_reconciliation_summary IS
'Executive summary of data trust metrics for the last 60 days';
