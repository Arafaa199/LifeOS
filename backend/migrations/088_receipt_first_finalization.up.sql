-- Migration: 088_receipt_first_finalization
-- Purpose: Receipt-first finalization — total_amount is sufficient, reconciliation is advisory
-- Principle: If a receipt has a total_amount, create the transaction. Mismatches surface as warnings, not silence.
-- Created: 2026-01-28

-- ============================================================================
-- 1. FINALIZE_RECEIPT v3 — Receipt-First
-- ============================================================================
-- Changes from v2 (migration 020):
--   - No longer blocks on zero items if total_amount is known
--   - Reconciliation is advisory (logs warning in parse_error, still creates transaction)
--   - Vendor-aware merchant name (not hardcoded Carrefour)
--   - Sets source = 'receipt' on created transactions
--   - Advisory warnings: parse_status = 'success' + parse_error IS NOT NULL

CREATE OR REPLACE FUNCTION finance.finalize_receipt(p_receipt_id INTEGER)
RETURNS JSONB AS $$
DECLARE
    v_receipt RECORD;
    v_items_total NUMERIC(10,2);
    v_item_count INTEGER;
    v_txn_id INTEGER;
    v_client_id VARCHAR(70);
    v_final_total NUMERIC(10,2);
    v_final_date DATE;
    v_computed_total NUMERIC(10,2);
    v_diff NUMERIC(10,2);
    v_merchant_name TEXT;
    v_reconciliation_warning TEXT;
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
    v_reconciliation_warning := NULL;

    -- Already linked? Return early (idempotent)
    IF v_receipt.linked_transaction_id IS NOT NULL THEN
        RETURN jsonb_build_object(
            'status', 'already_finalized',
            'receipt_id', p_receipt_id,
            'transaction_id', v_receipt.linked_transaction_id
        );
    END IF;

    -- Receipt-first: skip only if we have NOTHING to work with
    IF v_item_count = 0 AND v_receipt.total_amount IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'skipped',
            'reason', 'No items and no total_amount',
            'receipt_id', p_receipt_id
        );
    END IF;

    -- Determine final total
    IF v_receipt.total_amount IS NOT NULL THEN
        -- Receipt total is source of truth
        v_final_total := v_receipt.total_amount;

        -- Advisory reconciliation: if items exist, check they match
        IF v_item_count > 0 THEN
            v_computed_total := v_items_total
                + COALESCE(v_receipt.vat_amount, 0)
                + COALESCE((v_receipt.parsed_json->>'delivery_charge')::NUMERIC, 0)
                - COALESCE((v_receipt.parsed_json->>'discount_amount')::NUMERIC, 0);

            v_diff := ABS(v_computed_total - v_receipt.total_amount);

            IF v_diff > 0.01 THEN
                v_reconciliation_warning := format(
                    'Advisory: items=%.2f + VAT=%.2f + delivery=%.2f - discount=%.2f = computed=%.2f vs total=%.2f (diff=%.2f). Used total_amount.',
                    v_items_total,
                    COALESCE(v_receipt.vat_amount, 0),
                    COALESCE((v_receipt.parsed_json->>'delivery_charge')::NUMERIC, 0),
                    COALESCE((v_receipt.parsed_json->>'discount_amount')::NUMERIC, 0),
                    v_computed_total,
                    v_receipt.total_amount,
                    v_diff
                );
            END IF;
        ELSE
            -- No items but total exists — receipt-first finalization
            v_reconciliation_warning := 'Finalized from total_amount only (no line items)';
        END IF;
    ELSE
        -- No total_amount, compute from items (must have items — checked above)
        v_final_total := v_items_total;
    END IF;

    -- Determine final date
    v_final_date := COALESCE(
        v_receipt.receipt_date,
        (v_receipt.email_received_at AT TIME ZONE 'Asia/Dubai')::DATE,
        v_receipt.created_at::DATE
    );

    -- Vendor-aware merchant name
    v_merchant_name := CASE v_receipt.vendor
        WHEN 'carrefour_uae' THEN COALESCE('Carrefour ' || v_receipt.store_name, 'Carrefour')
        WHEN 'careem_quik'   THEN 'Careem Quik'
        ELSE COALESCE(v_receipt.vendor, 'Unknown Vendor')
    END;

    -- Idempotent client_id
    v_client_id := 'rcpt:' || v_receipt.pdf_hash;

    -- Find or create transaction
    SELECT id INTO v_txn_id
    FROM finance.transactions
    WHERE client_id = v_client_id;

    IF v_txn_id IS NULL THEN
        INSERT INTO finance.transactions (
            date, transaction_at, merchant_name, amount, currency,
            category, is_grocery, client_id, source, notes, receipt_processed
        ) VALUES (
            v_final_date,
            COALESCE(v_receipt.receipt_datetime, v_receipt.email_received_at, v_receipt.created_at),
            v_merchant_name,
            -ABS(v_final_total),
            COALESCE(v_receipt.currency, 'AED'),
            'Grocery', TRUE, v_client_id, 'receipt',
            format('Auto-created from receipt #%s', p_receipt_id),
            TRUE
        )
        RETURNING id INTO v_txn_id;
    END IF;

    -- Update receipt: always 'success', warnings go in parse_error
    UPDATE finance.receipts SET
        total_amount = v_final_total,
        receipt_date = v_final_date,
        linked_transaction_id = v_txn_id,
        link_method = 'auto_finalize',
        link_confidence = CASE WHEN v_reconciliation_warning IS NULL THEN 1.00 ELSE 0.80 END,
        linked_at = NOW(),
        parsed_at = COALESCE(parsed_at, NOW()),
        parse_status = 'success',
        parse_error = v_reconciliation_warning,
        updated_at = NOW()
    WHERE id = p_receipt_id;

    RETURN jsonb_build_object(
        'status', 'finalized',
        'receipt_id', p_receipt_id,
        'transaction_id', v_txn_id,
        'total_amount', v_final_total,
        'merchant', v_merchant_name,
        'receipt_date', v_final_date,
        'item_count', v_item_count,
        'client_id', v_client_id,
        'warning', v_reconciliation_warning
    );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION finance.finalize_receipt(INTEGER) IS
'Receipt-first finalization: creates transaction from total_amount even without items. Reconciliation is advisory.';

-- ============================================================================
-- 2. FINALIZE_PENDING_RECEIPTS v2 — Includes needs_review + total-only
-- ============================================================================

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
    FOR v_receipt IN
        SELECT r.id
        FROM finance.receipts r
        WHERE r.linked_transaction_id IS NULL
          AND r.parse_status IN ('pending', 'success', 'needs_review')
          AND (
              EXISTS (SELECT 1 FROM finance.receipt_items ri WHERE ri.receipt_id = r.id)
              OR r.total_amount IS NOT NULL
          )
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

COMMENT ON FUNCTION finance.finalize_pending_receipts() IS
'Batch finalize all pending/needs_review receipts that have items or total_amount';

-- ============================================================================
-- 3. BACKFILL — Fix existing receipt-created transactions
-- ============================================================================

-- Set source = 'receipt' and receipt_processed = true on all receipt-created transactions
UPDATE finance.transactions
SET source = 'receipt', receipt_processed = true
WHERE notes LIKE 'Auto-created from receipt%'
  AND (source != 'receipt' OR receipt_processed != true);

-- Fix Careem Quik merchant name (receipt 54 -> transaction 2224)
UPDATE finance.transactions
SET merchant_name = 'Careem Quik',
    merchant_name_clean = 'Careem Quik'
WHERE id = 2224
  AND notes = 'Auto-created from receipt #54'
  AND merchant_name = 'Carrefour';
