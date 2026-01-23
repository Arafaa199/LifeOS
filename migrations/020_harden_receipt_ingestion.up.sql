-- Migration: 020_harden_receipt_ingestion
-- Purpose: Harden receipt ingestion with full hashes, strict constraints, and better reconciliation
-- Created: 2026-01-23

-- ============================================================================
-- 1. EXPAND transactions.client_id TO HOLD FULL SHA256
-- ============================================================================
-- Current: varchar(36) = 'rcpt:' + 31 chars (truncated)
-- New: varchar(70) = 'rcpt:' + 64 chars (full SHA256) + margin

ALTER TABLE finance.transactions
    ALTER COLUMN client_id TYPE VARCHAR(70);

-- ============================================================================
-- 2. UPDATE EXISTING TRUNCATED CLIENT_IDS TO FULL HASH
-- ============================================================================

UPDATE finance.transactions t
SET client_id = 'rcpt:' || r.pdf_hash
FROM finance.receipts r
WHERE t.client_id = 'rcpt:' || LEFT(r.pdf_hash, 31)
  AND t.client_id LIKE 'rcpt:%';

-- ============================================================================
-- 3. ADD UNIQUE CONSTRAINT ON transactions.client_id (non-null only)
-- ============================================================================
-- Note: idx_transactions_client_id already exists as UNIQUE, but let's ensure it's correct

DROP INDEX IF EXISTS finance.idx_transactions_client_id;
CREATE UNIQUE INDEX idx_transactions_client_id
    ON finance.transactions(client_id)
    WHERE client_id IS NOT NULL;

-- ============================================================================
-- 4. VERIFY receipts.pdf_hash IS UNIQUE (already exists, just document)
-- ============================================================================
-- receipts_pdf_hash_key already exists from original schema

-- ============================================================================
-- 5. UPDATE finalize_receipt() TO USE FULL HASH AND HANDLE FEES
-- ============================================================================

CREATE OR REPLACE FUNCTION finance.finalize_receipt(p_receipt_id INTEGER)
RETURNS JSONB AS $$
DECLARE
    v_receipt RECORD;
    v_items_total NUMERIC(10,2);
    v_item_count INTEGER;
    v_txn_id INTEGER;
    v_client_id VARCHAR(70);  -- Full hash now
    v_final_total NUMERIC(10,2);
    v_final_date DATE;
    v_computed_total NUMERIC(10,2);
    v_diff NUMERIC(10,2);
BEGIN
    -- Lock the receipt row for update
    SELECT r.*,
           (SELECT COUNT(*) FROM finance.receipt_items ri WHERE ri.receipt_id = r.id) as item_count,
           (SELECT COALESCE(SUM(line_total), 0) FROM finance.receipt_items ri WHERE ri.receipt_id = r.id) as items_total
    INTO v_receipt
    FROM finance.receipts r
    WHERE r.id = p_receipt_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'error', 'error', 'Receipt not found');
    END IF;

    v_item_count := v_receipt.item_count;
    v_items_total := v_receipt.items_total;

    -- Must have items to finalize
    IF v_item_count = 0 THEN
        RETURN jsonb_build_object(
            'status', 'skipped',
            'reason', 'No items found',
            'receipt_id', p_receipt_id
        );
    END IF;

    -- Already linked? Just return success
    IF v_receipt.linked_transaction_id IS NOT NULL THEN
        RETURN jsonb_build_object(
            'status', 'already_finalized',
            'receipt_id', p_receipt_id,
            'transaction_id', v_receipt.linked_transaction_id
        );
    END IF;

    -- Compute expected total: items + VAT + delivery - discounts
    -- These fields come from parsed_json if available
    v_computed_total := v_items_total
        + COALESCE(v_receipt.vat_amount, 0)
        + COALESCE((v_receipt.parsed_json->>'delivery_charge')::NUMERIC, 0)
        - COALESCE((v_receipt.parsed_json->>'discount_amount')::NUMERIC, 0);

    -- Determine final total with reconciliation
    IF v_receipt.total_amount IS NOT NULL THEN
        -- Strict reconciliation: computed must match within 0.01
        v_diff := ABS(v_computed_total - v_receipt.total_amount);

        IF v_diff > 0.01 THEN
            -- Mark for review with detailed breakdown
            UPDATE finance.receipts SET
                parse_status = 'needs_review',
                parse_error = format(
                    'Reconciliation failed (tolerance 0.01): items=%.2f + VAT=%.2f + delivery=%.2f - discount=%.2f = computed=%.2f != total=%.2f (diff=%.2f)',
                    v_items_total,
                    COALESCE(v_receipt.vat_amount, 0),
                    COALESCE((v_receipt.parsed_json->>'delivery_charge')::NUMERIC, 0),
                    COALESCE((v_receipt.parsed_json->>'discount_amount')::NUMERIC, 0),
                    v_computed_total,
                    v_receipt.total_amount,
                    v_diff
                ),
                updated_at = NOW()
            WHERE id = p_receipt_id;

            RETURN jsonb_build_object(
                'status', 'needs_review',
                'reason', 'Reconciliation failed',
                'items_total', v_items_total,
                'vat_amount', COALESCE(v_receipt.vat_amount, 0),
                'delivery_charge', COALESCE((v_receipt.parsed_json->>'delivery_charge')::NUMERIC, 0),
                'discount_amount', COALESCE((v_receipt.parsed_json->>'discount_amount')::NUMERIC, 0),
                'computed_total', v_computed_total,
                'receipt_total', v_receipt.total_amount,
                'diff', v_diff
            );
        END IF;
        v_final_total := v_receipt.total_amount;
    ELSE
        -- No total on receipt, use computed
        v_final_total := v_computed_total;
    END IF;

    -- Determine final date
    v_final_date := COALESCE(
        v_receipt.receipt_date,
        (v_receipt.email_received_at AT TIME ZONE 'Asia/Dubai')::DATE,
        v_receipt.created_at::DATE
    );

    -- Generate idempotent client_id with FULL pdf_hash (no truncation)
    v_client_id := 'rcpt:' || v_receipt.pdf_hash;

    -- Try to find existing transaction with this client_id
    SELECT id INTO v_txn_id
    FROM finance.transactions
    WHERE client_id = v_client_id;

    IF v_txn_id IS NULL THEN
        -- Create new transaction
        INSERT INTO finance.transactions (
            date,
            transaction_at,
            merchant_name,
            amount,
            currency,
            category,
            is_grocery,
            client_id,
            notes,
            receipt_processed
        ) VALUES (
            v_final_date,
            COALESCE(v_receipt.receipt_datetime, v_receipt.email_received_at, v_receipt.created_at),
            COALESCE('Carrefour ' || v_receipt.store_name, 'Carrefour'),
            -ABS(v_final_total),  -- Expenses are negative
            COALESCE(v_receipt.currency, 'AED'),
            'Grocery',
            TRUE,
            v_client_id,
            format('Auto-created from receipt #%s', p_receipt_id),
            TRUE
        )
        RETURNING id INTO v_txn_id;
    END IF;

    -- Update receipt with finalized data
    UPDATE finance.receipts SET
        total_amount = v_final_total,
        receipt_date = v_final_date,
        linked_transaction_id = v_txn_id,
        link_method = 'auto_finalize',
        link_confidence = 1.00,
        linked_at = NOW(),
        parsed_at = COALESCE(parsed_at, NOW()),
        parse_status = 'success',
        parse_error = NULL,
        updated_at = NOW()
    WHERE id = p_receipt_id;

    RETURN jsonb_build_object(
        'status', 'finalized',
        'receipt_id', p_receipt_id,
        'transaction_id', v_txn_id,
        'total_amount', v_final_total,
        'receipt_date', v_final_date,
        'item_count', v_item_count,
        'client_id', v_client_id
    );
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- 6. RECEIPT STATUS REPORT VIEW
-- ============================================================================

CREATE OR REPLACE VIEW finance.receipt_status_report AS
SELECT
    parse_status,
    CASE
        WHEN item_count > 0 THEN 'with_items'
        ELSE 'no_items'
    END as item_status,
    COUNT(*) as count,
    SUM(CASE WHEN linked_transaction_id IS NOT NULL THEN 1 ELSE 0 END) as linked,
    SUM(CASE WHEN total_amount IS NOT NULL THEN 1 ELSE 0 END) as has_total,
    array_agg(id ORDER BY id) as receipt_ids
FROM (
    SELECT
        r.id,
        r.parse_status,
        r.linked_transaction_id,
        r.total_amount,
        (SELECT COUNT(*) FROM finance.receipt_items ri WHERE ri.receipt_id = r.id) as item_count
    FROM finance.receipts r
) sub
GROUP BY parse_status, item_status
ORDER BY parse_status, item_status;

COMMENT ON VIEW finance.receipt_status_report IS
'Shows receipts grouped by parse_status and whether they have items';


-- ============================================================================
-- 7. PENDING RECEIPTS DETAIL FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION finance.pending_receipts_detail()
RETURNS TABLE (
    receipt_id INTEGER,
    vendor VARCHAR(50),
    store_name VARCHAR(200),
    receipt_date DATE,
    total_amount NUMERIC(10,2),
    parse_status VARCHAR(20),
    item_count BIGINT,
    items_total NUMERIC,
    has_pdf BOOLEAN,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        r.id as receipt_id,
        r.vendor,
        r.store_name,
        r.receipt_date,
        r.total_amount,
        r.parse_status,
        (SELECT COUNT(*) FROM finance.receipt_items ri WHERE ri.receipt_id = r.id) as item_count,
        (SELECT COALESCE(SUM(line_total), 0) FROM finance.receipt_items ri WHERE ri.receipt_id = r.id) as items_total,
        (r.pdf_storage_path IS NOT NULL AND r.pdf_storage_path != '') as has_pdf,
        r.created_at
    FROM finance.receipts r
    WHERE r.linked_transaction_id IS NULL
    ORDER BY
        CASE WHEN (SELECT COUNT(*) FROM finance.receipt_items ri WHERE ri.receipt_id = r.id) > 0 THEN 0 ELSE 1 END,
        r.created_at DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION finance.pending_receipts_detail() IS
'Returns detailed info about pending (unlinked) receipts, sorted with items-having receipts first';
