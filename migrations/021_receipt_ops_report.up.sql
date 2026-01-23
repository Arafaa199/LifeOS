-- Migration: 021_receipt_ops_report
-- Purpose: Add ops report view for receipt ingestion monitoring
-- Created: 2026-01-23

-- ============================================================================
-- RECEIPT OPS REPORT VIEW
-- ============================================================================

CREATE OR REPLACE VIEW finance.receipt_ops_report AS
WITH stats AS (
    SELECT
        -- Last 24 hours counts
        COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '24 hours') as receipts_24h,
        COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '24 hours' AND parse_status = 'success') as success_24h,
        COUNT(*) FILTER (WHERE parse_status = 'needs_review') as needs_review,
        COUNT(*) FILTER (WHERE parse_status = 'failed') as failed,
        COUNT(*) FILTER (WHERE parse_status = 'pending' AND EXISTS (
            SELECT 1 FROM finance.receipt_items ri WHERE ri.receipt_id = receipts.id
        )) as pending_with_items,
        COUNT(*) FILTER (WHERE parse_status = 'pending' AND NOT EXISTS (
            SELECT 1 FROM finance.receipt_items ri WHERE ri.receipt_id = receipts.id
        )) as pending_no_items,
        COUNT(*) FILTER (WHERE linked_transaction_id IS NOT NULL) as total_linked,
        COUNT(*) as total_receipts,
        -- Last success timestamp
        MAX(CASE WHEN parse_status = 'success' AND linked_transaction_id IS NOT NULL THEN linked_at END) as last_success_at,
        -- Last ingestion timestamp
        MAX(created_at) as last_ingested_at
    FROM finance.receipts
)
SELECT
    receipts_24h,
    success_24h,
    needs_review,
    failed,
    pending_with_items,
    pending_no_items,
    total_linked,
    total_receipts,
    last_success_at,
    last_ingested_at,
    -- Health indicator
    CASE
        WHEN needs_review > 0 OR failed > 0 THEN 'warning'
        WHEN pending_with_items > 0 THEN 'action_needed'
        WHEN last_success_at > NOW() - INTERVAL '7 days' THEN 'healthy'
        ELSE 'stale'
    END as health_status
FROM stats;

COMMENT ON VIEW finance.receipt_ops_report IS
'Ops dashboard for receipt ingestion: receipts_24h, needs_review, failed, last_success_at';


-- ============================================================================
-- RECEIPT OPS DETAIL FUNCTION
-- ============================================================================
-- Returns receipts needing attention (needs_review, failed, pending_with_items)

CREATE OR REPLACE FUNCTION finance.receipt_ops_detail()
RETURNS TABLE (
    receipt_id INTEGER,
    parse_status VARCHAR(20),
    vendor VARCHAR(50),
    store_name VARCHAR(200),
    total_amount NUMERIC(10,2),
    item_count BIGINT,
    parse_error TEXT,
    created_at TIMESTAMPTZ,
    attention_reason TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        r.id as receipt_id,
        r.parse_status,
        r.vendor,
        r.store_name,
        r.total_amount,
        (SELECT COUNT(*) FROM finance.receipt_items ri WHERE ri.receipt_id = r.id) as item_count,
        r.parse_error,
        r.created_at,
        CASE
            WHEN r.parse_status = 'needs_review' THEN 'Reconciliation or template issue'
            WHEN r.parse_status = 'failed' THEN 'Parse failed'
            WHEN r.parse_status = 'pending' AND EXISTS (
                SELECT 1 FROM finance.receipt_items ri WHERE ri.receipt_id = r.id
            ) THEN 'Has items but not finalized'
            ELSE 'Unknown'
        END as attention_reason
    FROM finance.receipts r
    WHERE r.parse_status IN ('needs_review', 'failed')
       OR (r.parse_status = 'pending' AND EXISTS (
           SELECT 1 FROM finance.receipt_items ri WHERE ri.receipt_id = r.id
       ))
    ORDER BY
        CASE r.parse_status
            WHEN 'failed' THEN 1
            WHEN 'needs_review' THEN 2
            ELSE 3
        END,
        r.created_at DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION finance.receipt_ops_detail() IS
'Returns receipts needing attention with reason for each';
