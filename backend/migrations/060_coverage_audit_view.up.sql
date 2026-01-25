-- Migration: 060_coverage_audit_view.up.sql
-- Purpose: Create coverage audit view for SMS → Transaction gap detection
-- Date: 2026-01-25

-- ============================================================================
-- View: finance.v_coverage_gaps
-- Purpose: Identify days where SMS received but transactions not created
-- Uses: raw.sms_classifications (from SMS classifier) + finance.transactions
-- ============================================================================

CREATE OR REPLACE VIEW finance.v_coverage_gaps AS
WITH sms_days AS (
    SELECT
        DATE(received_at AT TIME ZONE 'Asia/Dubai') as sms_date,
        COUNT(*) as sms_count,
        COUNT(*) FILTER (WHERE canonical_intent IN ('FIN_TXN_APPROVED', 'FIN_TXN_REFUND')) as financial_sms,
        COUNT(*) FILTER (WHERE created_transaction = true) as sms_with_tx,
        COUNT(*) FILTER (WHERE canonical_intent IN ('FIN_TXN_APPROVED', 'FIN_TXN_REFUND')
                         AND created_transaction = false) as sms_missing_tx
    FROM raw.sms_classifications
    WHERE received_at >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY 1
),
tx_days AS (
    SELECT
        date as tx_date,
        COUNT(*) as tx_count,
        COUNT(*) FILTER (WHERE external_id LIKE 'sms:%') as sms_tx_count
    FROM finance.transactions
    WHERE date >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY 1
)
SELECT
    COALESCE(s.sms_date, t.tx_date) as date,
    COALESCE(s.sms_count, 0) as sms_received,
    COALESCE(s.financial_sms, 0) as financial_sms,
    COALESCE(s.sms_with_tx, 0) as sms_with_tx,
    COALESCE(s.sms_missing_tx, 0) as sms_missing_tx,
    COALESCE(t.tx_count, 0) as transactions_created,
    COALESCE(t.sms_tx_count, 0) as sms_transactions,
    CASE
        WHEN COALESCE(s.financial_sms, 0) = 0 THEN 'NO_SMS'
        WHEN COALESCE(s.sms_missing_tx, 0) = 0 THEN 'OK'
        WHEN COALESCE(s.sms_missing_tx, 0) <= 2 THEN 'MINOR_GAP'
        ELSE 'GAP'
    END as status,
    COALESCE(s.sms_missing_tx, 0) as missing_count
FROM sms_days s
FULL OUTER JOIN tx_days t ON s.sms_date = t.tx_date
ORDER BY date DESC;

COMMENT ON VIEW finance.v_coverage_gaps IS
'Audit view showing days with SMS coverage gaps. Joins SMS classifications with transactions to identify missing transaction creation.';

-- ============================================================================
-- View: finance.v_coverage_summary
-- Purpose: Executive summary of coverage metrics
-- ============================================================================

CREATE OR REPLACE VIEW finance.v_coverage_summary AS
SELECT
    COUNT(*) as days_tracked,
    SUM(sms_received) as total_sms,
    SUM(financial_sms) as total_financial_sms,
    SUM(sms_with_tx) as total_captured,
    SUM(missing_count) as total_missing,
    ROUND(SUM(sms_with_tx)::numeric / NULLIF(SUM(financial_sms), 0)::numeric, 3) as capture_rate,
    COUNT(*) FILTER (WHERE status IN ('GAP', 'MINOR_GAP')) as days_with_gaps,
    MIN(date) as earliest_date,
    MAX(date) as latest_date
FROM finance.v_coverage_gaps
WHERE status != 'NO_SMS';

COMMENT ON VIEW finance.v_coverage_summary IS
'Executive summary of SMS → Transaction capture rate for last 30 days.';

-- ============================================================================
-- View: finance.v_orphan_raw_events
-- Purpose: Show raw_events without linked transactions
-- ============================================================================

CREATE OR REPLACE VIEW finance.v_orphan_raw_events AS
SELECT
    re.id,
    re.source,
    re.event_type,
    re.client_id,
    re.payload->>'amount' as amount,
    re.payload->>'currency' as currency,
    re.payload->>'merchant' as merchant,
    re.created_at,
    re.validation_status,
    t.id as transaction_id,
    CASE
        WHEN t.id IS NOT NULL THEN 'linked'
        WHEN re.validation_status IN ('ignored', 'invalid') THEN 'resolved'
        WHEN re.created_at < NOW() - INTERVAL '15 minutes' THEN 'orphan'
        ELSE 'pending'
    END as resolution_status
FROM finance.raw_events re
LEFT JOIN finance.transactions t ON re.client_id = t.client_id
WHERE re.source = 'sms'
  AND re.created_at >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY re.created_at DESC;

COMMENT ON VIEW finance.v_orphan_raw_events IS
'Shows raw_events from SMS ingestion with their transaction linkage status. Orphans are events older than 15 minutes without a linked transaction.';
