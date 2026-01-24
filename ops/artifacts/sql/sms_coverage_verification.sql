-- SMS Coverage Verification Queries
-- Purpose: Verify SMS financial coverage is trustworthy
-- Date: 2026-01-25

-- ============================================================================
-- Q1: Days with missing coverage
-- ============================================================================
SELECT
    day,
    total_messages,
    should_have_tx,
    did_create_tx,
    missing_tx_count,
    coverage_score,
    coverage_status
FROM raw.sms_daily_coverage
WHERE coverage_status != 'COMPLETE'
ORDER BY day DESC;

-- ============================================================================
-- Q2: Messages ignored (by intent)
-- ============================================================================
SELECT
    canonical_intent,
    COUNT(*) AS count,
    string_agg(DISTINCT sender, ', ') AS senders
FROM raw.sms_classifications
WHERE canonical_intent IN ('IGNORE', 'FIN_INFO_ONLY', 'FIN_AUTH_CODE', 'FIN_SECURITY_ALERT', 'FIN_LOGIN_ALERT')
GROUP BY canonical_intent
ORDER BY count DESC;

-- ============================================================================
-- Q3: Messages declined vs approved
-- ============================================================================
SELECT
    canonical_intent,
    COUNT(*) AS count,
    COUNT(*) FILTER (WHERE created_transaction) AS with_tx,
    ROUND(AVG(confidence)::NUMERIC, 2) AS avg_confidence,
    ROUND(SUM(COALESCE(amount, 0))::NUMERIC, 2) AS total_amount
FROM raw.sms_classifications
WHERE canonical_intent IN ('FIN_TXN_APPROVED', 'FIN_TXN_DECLINED', 'FIN_TXN_REFUND')
GROUP BY canonical_intent
ORDER BY count DESC;

-- ============================================================================
-- Q4: Coverage summary (single row)
-- ============================================================================
SELECT * FROM raw.sms_coverage_summary;

-- ============================================================================
-- Q5: Missing transactions detail (what needs backfill)
-- ============================================================================
SELECT
    sender,
    DATE(received_at AT TIME ZONE 'Asia/Dubai') AS day,
    canonical_intent,
    amount,
    currency,
    merchant,
    pattern_name
FROM raw.sms_missing_transactions
ORDER BY received_at DESC;

-- ============================================================================
-- Q6: Intent breakdown with transaction coverage
-- ============================================================================
SELECT * FROM raw.sms_intent_breakdown;

-- ============================================================================
-- Q7: Daily financial totals from SMS (should match finance.daily_totals_aed)
-- ============================================================================
WITH sms_totals AS (
    SELECT
        DATE(received_at AT TIME ZONE 'Asia/Dubai') AS day,
        SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END) AS sms_expense,
        SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) AS sms_income
    FROM raw.sms_classifications
    WHERE created_transaction = TRUE
      AND currency = 'AED'
    GROUP BY DATE(received_at AT TIME ZONE 'Asia/Dubai')
)
SELECT
    s.day,
    s.sms_expense,
    s.sms_income,
    COALESCE(d.expense_aed, 0) AS canonical_expense,
    COALESCE(d.income_aed, 0) AS canonical_income,
    CASE
        WHEN ABS(s.sms_expense - COALESCE(d.expense_aed, 0)) < 1 THEN 'MATCH'
        ELSE 'MISMATCH'
    END AS expense_status
FROM sms_totals s
LEFT JOIN finance.daily_totals_aed d ON d.day = s.day
WHERE s.day >= CURRENT_DATE - 30
ORDER BY s.day DESC;
