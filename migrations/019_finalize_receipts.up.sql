-- Migration: 019_finalize_receipts
-- Purpose: Add atomic finalize function for receipts with items
-- Created: 2026-01-23

-- ============================================================================
-- FINALIZE RECEIPT FUNCTION
-- ============================================================================
-- Atomically finalizes a receipt:
--   1. Computes total_amount from items if NULL
--   2. Sets receipt_date from email_received_at if NULL
--   3. Sets parsed_at if NULL
--   4. Creates transaction with idempotent client_id
--   5. Links receipt to transaction
--
-- Returns: JSON with status and details

CREATE OR REPLACE FUNCTION finance.finalize_receipt(p_receipt_id INTEGER)
RETURNS JSONB AS $$
DECLARE
    v_receipt RECORD;
    v_items_total NUMERIC(10,2);
    v_item_count INTEGER;
    v_txn_id INTEGER;
    v_client_id VARCHAR(36);
    v_final_total NUMERIC(10,2);
    v_final_date DATE;
    v_result JSONB;
BEGIN
    -- Lock the receipt row for update
    SELECT r.*,
           (SELECT COUNT(*) FROM finance.receipt_items WHERE receipt_id = r.id) as item_count,
           (SELECT COALESCE(SUM(line_total), 0) FROM finance.receipt_items WHERE receipt_id = r.id) as items_total
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

    -- Determine final total: use existing or compute from items
    IF v_receipt.total_amount IS NOT NULL THEN
        -- Reconciliation check: items must match within tolerance
        IF ABS(v_items_total - v_receipt.total_amount) > 0.01 THEN
            -- Mark for review instead of failing
            UPDATE finance.receipts SET
                parse_status = 'needs_review',
                parse_error = format('Reconciliation: items sum %.2f != total %.2f (diff: %.2f)',
                                     v_items_total, v_receipt.total_amount,
                                     ABS(v_items_total - v_receipt.total_amount)),
                updated_at = NOW()
            WHERE id = p_receipt_id;

            RETURN jsonb_build_object(
                'status', 'needs_review',
                'reason', 'Reconciliation failed',
                'items_total', v_items_total,
                'receipt_total', v_receipt.total_amount,
                'diff', ABS(v_items_total - v_receipt.total_amount)
            );
        END IF;
        v_final_total := v_receipt.total_amount;
    ELSE
        -- Compute from items
        v_final_total := v_items_total;
    END IF;

    -- Determine final date
    v_final_date := COALESCE(
        v_receipt.receipt_date,
        (v_receipt.email_received_at AT TIME ZONE 'Asia/Dubai')::DATE,
        v_receipt.created_at::DATE
    );

    -- Generate idempotent client_id: "rcpt:" + first 31 chars of pdf_hash (36 total for varchar(36))
    v_client_id := 'rcpt:' || LEFT(v_receipt.pdf_hash, 31);

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
-- BATCH FINALIZE FUNCTION
-- ============================================================================
-- Finalizes all pending receipts that have items

CREATE OR REPLACE FUNCTION finance.finalize_pending_receipts()
RETURNS TABLE (
    receipt_id INTEGER,
    status TEXT,
    details JSONB
) AS $$
DECLARE
    v_receipt RECORD;
    v_result JSONB;
BEGIN
    -- Find all receipts with items that need finalization
    FOR v_receipt IN
        SELECT r.id
        FROM finance.receipts r
        WHERE r.linked_transaction_id IS NULL
          AND r.parse_status IN ('pending', 'success')  -- Include success without txn
          AND EXISTS (SELECT 1 FROM finance.receipt_items ri WHERE ri.receipt_id = r.id)
        ORDER BY r.id
    LOOP
        v_result := finance.finalize_receipt(v_receipt.id);

        receipt_id := v_receipt.id;
        status := v_result->>'status';
        details := v_result;

        RETURN NEXT;
    END LOOP;
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON FUNCTION finance.finalize_receipt(INTEGER) IS
'Atomically finalizes a receipt: computes total from items if needed, creates transaction, links them';

COMMENT ON FUNCTION finance.finalize_pending_receipts() IS
'Batch finalize all pending receipts that have items';
