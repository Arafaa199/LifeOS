-- M6.6 Coverage Dashboard Queries
-- Purpose: CLI snippets for checking daily coverage status
-- Date: 2026-01-25

-- ============================================================================
-- Q1: Daily Coverage Status (last 7 days)
-- ============================================================================
SELECT
    day,
    sms_coverage_pct AS sms_cov,
    receipt_count AS receipts,
    receipts_linked AS linked,
    tx_count AS txns,
    anomaly_count AS anomalies,
    overall_status AS status
FROM finance.daily_coverage_status
WHERE day >= CURRENT_DATE - 7
ORDER BY day DESC;

-- ============================================================================
-- Q2: Coverage Summary (single row)
-- ============================================================================
SELECT * FROM finance.coverage_summary;

-- ============================================================================
-- Q3: Days with Issues
-- ============================================================================
SELECT
    day,
    overall_status,
    CASE
        WHEN overall_status = 'SMS_GAPS' THEN
            'SMS coverage: ' || ROUND(sms_coverage_pct * 100) || '% (' || sms_actual_tx || '/' || sms_expected_tx || ')'
        WHEN overall_status = 'RECEIPTS_UNLINKED' THEN
            'Unlinked receipts: ' || (receipt_count - receipts_linked) || '/' || receipt_count
        WHEN overall_status = 'HAS_ANOMALIES' THEN
            'Anomalies: ' || anomaly_count || ' (' || array_to_string(anomalies, ', ') || ')'
        ELSE 'No issues'
    END AS details
FROM finance.daily_coverage_status
WHERE overall_status NOT IN ('OK', 'NO_DATA')
ORDER BY day DESC;

-- ============================================================================
-- Q4: Quick Health Check (run this daily)
-- ============================================================================
SELECT
    CURRENT_DATE AS checked_at,
    days_ok || '/' || days_tracked AS days_ok,
    ROUND(avg_sms_coverage * 100) || '%' AS sms_coverage,
    total_receipts_linked || '/' || total_receipts AS receipts_linked,
    total_anomalies AS anomalies,
    CASE
        WHEN days_sms_gaps > 3 THEN 'SMS CRITICAL'
        WHEN total_receipts > 0 AND overall_receipt_linked_pct < 0.5 THEN 'RECEIPTS NEED LINKING'
        WHEN total_anomalies > 5 THEN 'MANY ANOMALIES'
        ELSE 'HEALTHY'
    END AS overall_health
FROM finance.coverage_summary;
