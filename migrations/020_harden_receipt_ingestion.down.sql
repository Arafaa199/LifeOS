-- Migration: 020_harden_receipt_ingestion (rollback)

DROP FUNCTION IF EXISTS finance.pending_receipts_detail();
DROP VIEW IF EXISTS finance.receipt_status_report;

-- Restore original finalize_receipt function (truncated client_id)
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
BEGIN
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

    IF v_item_count = 0 THEN
        RETURN jsonb_build_object('status', 'skipped', 'reason', 'No items found', 'receipt_id', p_receipt_id);
    END IF;

    IF v_receipt.linked_transaction_id IS NOT NULL THEN
        RETURN jsonb_build_object('status', 'already_finalized', 'receipt_id', p_receipt_id, 'transaction_id', v_receipt.linked_transaction_id);
    END IF;

    IF v_receipt.total_amount IS NOT NULL THEN
        IF ABS(v_items_total - v_receipt.total_amount) > 0.01 THEN
            UPDATE finance.receipts SET parse_status = 'needs_review', parse_error = format('Reconciliation: items sum %.2f != total %.2f', v_items_total, v_receipt.total_amount), updated_at = NOW() WHERE id = p_receipt_id;
            RETURN jsonb_build_object('status', 'needs_review', 'reason', 'Reconciliation failed');
        END IF;
        v_final_total := v_receipt.total_amount;
    ELSE
        v_final_total := v_items_total;
    END IF;

    v_final_date := COALESCE(v_receipt.receipt_date, (v_receipt.email_received_at AT TIME ZONE 'Asia/Dubai')::DATE, v_receipt.created_at::DATE);
    v_client_id := 'rcpt:' || LEFT(v_receipt.pdf_hash, 31);

    SELECT id INTO v_txn_id FROM finance.transactions WHERE client_id = v_client_id;

    IF v_txn_id IS NULL THEN
        INSERT INTO finance.transactions (date, transaction_at, merchant_name, amount, currency, category, is_grocery, client_id, notes, receipt_processed)
        VALUES (v_final_date, COALESCE(v_receipt.receipt_datetime, v_receipt.email_received_at, v_receipt.created_at), COALESCE('Carrefour ' || v_receipt.store_name, 'Carrefour'), -ABS(v_final_total), COALESCE(v_receipt.currency, 'AED'), 'Grocery', TRUE, v_client_id, format('Auto-created from receipt #%s', p_receipt_id), TRUE)
        RETURNING id INTO v_txn_id;
    END IF;

    UPDATE finance.receipts SET total_amount = v_final_total, receipt_date = v_final_date, linked_transaction_id = v_txn_id, link_method = 'auto_finalize', link_confidence = 1.00, linked_at = NOW(), parsed_at = COALESCE(parsed_at, NOW()), parse_status = 'success', parse_error = NULL, updated_at = NOW() WHERE id = p_receipt_id;

    RETURN jsonb_build_object('status', 'finalized', 'receipt_id', p_receipt_id, 'transaction_id', v_txn_id, 'total_amount', v_final_total, 'receipt_date', v_final_date, 'item_count', v_item_count, 'client_id', v_client_id);
END;
$$ LANGUAGE plpgsql;

-- Shrink client_id back (data may be lost if full hashes exist)
-- Note: This may fail if data exceeds 36 chars
ALTER TABLE finance.transactions ALTER COLUMN client_id TYPE VARCHAR(36);
