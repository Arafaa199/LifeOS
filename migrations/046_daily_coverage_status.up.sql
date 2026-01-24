-- Migration: 046_daily_coverage_status.up.sql
-- Purpose: M6.6 - Daily Coverage Dashboard View
-- Date: 2026-01-25

-- ============================================================================
-- finance.daily_coverage_status
-- Single view showing daily data coverage across all sources
-- ============================================================================

CREATE OR REPLACE VIEW finance.daily_coverage_status AS
WITH date_range AS (
    -- Generate last 30 days
    SELECT generate_series(
        CURRENT_DATE - INTERVAL '30 days',
        CURRENT_DATE,
        '1 day'
    )::DATE AS day
),
sms_coverage AS (
    -- SMS transaction coverage from raw.sms_daily_coverage
    SELECT
        day,
        total_messages AS sms_messages,
        should_have_tx AS sms_expected_tx,
        did_create_tx AS sms_actual_tx,
        coverage_score AS sms_coverage_pct,
        coverage_status AS sms_status
    FROM raw.sms_daily_coverage
),
receipt_coverage AS (
    -- Receipt coverage by day
    SELECT
        COALESCE(receipt_date, email_received_at::DATE) AS day,
        COUNT(*) AS receipt_count,
        COUNT(*) FILTER (WHERE linked_transaction_id IS NOT NULL) AS receipts_linked,
        COUNT(*) FILTER (WHERE parse_status = 'success') AS receipts_parsed
    FROM finance.receipts
    WHERE COALESCE(receipt_date, email_received_at::DATE) IS NOT NULL
    GROUP BY COALESCE(receipt_date, email_received_at::DATE)
),
transaction_coverage AS (
    -- Transaction counts by day
    SELECT
        finance.to_business_date(transaction_at) AS day,
        COUNT(*) AS tx_count,
        COUNT(*) FILTER (WHERE amount < 0) AS expense_count,
        COUNT(*) FILTER (WHERE amount > 0) AS income_count,
        SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END) AS total_spent,
        SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) AS total_income
    FROM finance.transactions
    WHERE NOT is_quarantined
      AND transaction_at IS NOT NULL
    GROUP BY finance.to_business_date(transaction_at)
),
anomaly_coverage AS (
    -- Anomaly counts by day
    SELECT
        day,
        ARRAY_LENGTH(anomalies, 1) AS anomaly_count,
        anomalies
    FROM insights.daily_anomalies
    WHERE anomalies IS NOT NULL AND ARRAY_LENGTH(anomalies, 1) > 0
),
health_coverage AS (
    -- Health data coverage
    SELECT
        date AS day,
        COUNT(*) AS health_events,
        MAX(value) FILTER (WHERE metric_type = 'recovery') AS recovery,
        MAX(value) FILTER (WHERE metric_type = 'hrv') AS hrv
    FROM health.metrics
    GROUP BY date
)
SELECT
    dr.day,
    -- SMS Coverage
    COALESCE(s.sms_messages, 0) AS sms_messages,
    COALESCE(s.sms_expected_tx, 0) AS sms_expected_tx,
    COALESCE(s.sms_actual_tx, 0) AS sms_actual_tx,
    COALESCE(s.sms_coverage_pct, 1.0) AS sms_coverage_pct,
    COALESCE(s.sms_status, 'NO_DATA') AS sms_status,

    -- Receipt Coverage
    COALESCE(r.receipt_count, 0) AS receipt_count,
    COALESCE(r.receipts_linked, 0) AS receipts_linked,
    COALESCE(r.receipts_parsed, 0) AS receipts_parsed,
    CASE
        WHEN COALESCE(r.receipt_count, 0) = 0 THEN 1.0
        ELSE ROUND(COALESCE(r.receipts_linked, 0)::NUMERIC / r.receipt_count, 2)
    END AS receipt_linked_pct,

    -- Transaction Coverage
    COALESCE(t.tx_count, 0) AS tx_count,
    COALESCE(t.expense_count, 0) AS expense_count,
    COALESCE(t.income_count, 0) AS income_count,
    COALESCE(t.total_spent, 0) AS total_spent,
    COALESCE(t.total_income, 0) AS total_income,

    -- Health Coverage
    COALESCE(h.health_events, 0) AS health_events,
    h.recovery,
    h.hrv,

    -- Anomaly Coverage
    COALESCE(a.anomaly_count, 0) AS anomaly_count,
    a.anomalies,

    -- Overall Status
    CASE
        WHEN COALESCE(s.sms_coverage_pct, 1.0) < 0.9 THEN 'SMS_GAPS'
        WHEN COALESCE(r.receipt_count, 0) > 0 AND COALESCE(r.receipts_linked, 0) = 0 THEN 'RECEIPTS_UNLINKED'
        WHEN COALESCE(a.anomaly_count, 0) > 0 THEN 'HAS_ANOMALIES'
        WHEN COALESCE(t.tx_count, 0) = 0 AND COALESCE(h.health_events, 0) = 0 THEN 'NO_DATA'
        ELSE 'OK'
    END AS overall_status

FROM date_range dr
LEFT JOIN sms_coverage s ON s.day = dr.day
LEFT JOIN receipt_coverage r ON r.day = dr.day
LEFT JOIN transaction_coverage t ON t.day = dr.day
LEFT JOIN anomaly_coverage a ON a.day = dr.day
LEFT JOIN health_coverage h ON h.day = dr.day
ORDER BY dr.day DESC;

-- ============================================================================
-- finance.coverage_summary
-- Single-row summary for dashboard
-- ============================================================================

CREATE OR REPLACE VIEW finance.coverage_summary AS
SELECT
    COUNT(*) AS days_tracked,
    COUNT(*) FILTER (WHERE overall_status = 'OK') AS days_ok,
    COUNT(*) FILTER (WHERE overall_status = 'SMS_GAPS') AS days_sms_gaps,
    COUNT(*) FILTER (WHERE overall_status = 'RECEIPTS_UNLINKED') AS days_receipts_unlinked,
    COUNT(*) FILTER (WHERE overall_status = 'HAS_ANOMALIES') AS days_with_anomalies,
    COUNT(*) FILTER (WHERE overall_status = 'NO_DATA') AS days_no_data,
    ROUND(AVG(sms_coverage_pct)::NUMERIC, 3) AS avg_sms_coverage,
    SUM(sms_expected_tx) AS total_sms_expected,
    SUM(sms_actual_tx) AS total_sms_actual,
    SUM(receipt_count) AS total_receipts,
    SUM(receipts_linked) AS total_receipts_linked,
    CASE
        WHEN SUM(receipt_count) = 0 THEN 1.0
        ELSE ROUND(SUM(receipts_linked)::NUMERIC / SUM(receipt_count), 3)
    END AS overall_receipt_linked_pct,
    SUM(anomaly_count) AS total_anomalies,
    SUM(tx_count) AS total_transactions
FROM finance.daily_coverage_status;

COMMENT ON VIEW finance.daily_coverage_status IS 'M6.6: Daily coverage dashboard showing SMS, receipts, transactions, and anomalies per day';
COMMENT ON VIEW finance.coverage_summary IS 'M6.6: Single-row coverage summary for dashboard widgets';
