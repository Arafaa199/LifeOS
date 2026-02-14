-- Migration: 196_finance_grocery_dedup_cleanup
-- Purpose: Unify "Grocery" → "Groceries" everywhere, fix merchant rules, quarantine duplicate
--          SMS+receipt transactions, rewrite find_matching_transaction() to handle NULL receipt_date,
--          rewrite finalize_receipt() with dedup-before-insert, update dependent views.
-- Created: 2026-02-14

-- ============================================================================
-- 1. RENAME CATEGORY: Grocery → Groceries
-- ============================================================================

UPDATE finance.categories SET name = 'Groceries' WHERE id = 1 AND name = 'Grocery';

UPDATE finance.transactions SET category = 'Groceries' WHERE category = 'Grocery';

-- ============================================================================
-- 2. FIX MERCHANT RULES
-- ============================================================================

-- Rule 193 (CAREEM QUIK): wrong category, wrong category_id, wrong flags
UPDATE finance.merchant_rules
SET category = 'Groceries', category_id = 1, is_grocery = true, is_food_related = true
WHERE id = 193;

-- Blanket fix for any remaining Grocery → Groceries in merchant_rules
UPDATE finance.merchant_rules SET category = 'Groceries' WHERE category = 'Grocery';

-- Ensure Carrefour rules point to category_id = 1
UPDATE finance.merchant_rules
SET category_id = 1
WHERE id IN (156, 157, 276)
  AND category = 'Groceries';

-- ============================================================================
-- 3. FIX BAD MERCHANT NAMES
-- ============================================================================

UPDATE finance.transactions
SET merchant_name = 'Careem Quik',
    merchant_name_clean = 'Careem Quik',
    source = 'receipt',
    is_grocery = true,
    is_food_related = true
WHERE merchant_name = 'Carrefour Careem Quik';

-- ============================================================================
-- 4. QUARANTINE DUPLICATE TRANSACTIONS
-- ============================================================================
-- 4 confirmed SMS+receipt duplicate pairs. Keep the SMS transaction, quarantine the
-- receipt-sourced duplicate, relink the receipt row to the SMS transaction.

-- Helper: quarantine receipt dupes and relink
DO $$
DECLARE
    v_pair RECORD;
BEGIN
    -- (sms_txn_id, receipt_txn_id)
    FOR v_pair IN
        SELECT * FROM (VALUES
            (98908, 98920),
            (59724, 61416),
            (36086, 61418),
            (41638, 61417)
        ) AS pairs(sms_id, receipt_id)
    LOOP
        -- Quarantine the receipt-sourced duplicate
        UPDATE finance.transactions
        SET is_quarantined = true,
            notes = COALESCE(notes, '') || ' [quarantined by migration 196: duplicate of SMS txn ' || v_pair.sms_id || ']'
        WHERE id = v_pair.receipt_id
          AND is_quarantined = false;

        -- Relink any receipts from the quarantined txn to the SMS txn
        UPDATE finance.receipts
        SET linked_transaction_id = v_pair.sms_id,
            link_method = 'migration_196_relink',
            updated_at = NOW()
        WHERE linked_transaction_id = v_pair.receipt_id;

        -- Mark the SMS transaction as receipt_processed
        UPDATE finance.transactions
        SET receipt_processed = true
        WHERE id = v_pair.sms_id;
    END LOOP;
END $$;

-- ============================================================================
-- 5. REWRITE find_matching_transaction() — handle NULL receipt_date
-- ============================================================================

CREATE OR REPLACE FUNCTION finance.find_matching_transaction(
    p_receipt_id INTEGER
) RETURNS TABLE (
    transaction_id INTEGER,
    match_type VARCHAR(50),
    confidence NUMERIC(3,2)
) AS $$
DECLARE
    v_receipt RECORD;
    v_search_date DATE;
BEGIN
    SELECT receipt_date, total_amount, vendor, email_received_at, created_at
    INTO v_receipt
    FROM finance.receipts
    WHERE id = p_receipt_id;

    -- Fallback date: receipt_date → email_received_at → created_at
    v_search_date := COALESCE(
        v_receipt.receipt_date,
        (v_receipt.email_received_at AT TIME ZONE 'Asia/Dubai')::date,
        v_receipt.created_at::date
    );

    -- Exact match: same date + same amount
    RETURN QUERY
    SELECT
        t.id AS transaction_id,
        'exact_date_amount'::VARCHAR(50) AS match_type,
        1.00::NUMERIC(3,2) AS confidence
    FROM finance.transactions t
    WHERE t.date = v_search_date
      AND ABS(t.amount) = v_receipt.total_amount
      AND t.receipt_processed = FALSE
      AND t.is_quarantined = FALSE
    LIMIT 1;

    IF NOT FOUND THEN
        -- Fuzzy match: ±1 day + same amount
        RETURN QUERY
        SELECT
            t.id AS transaction_id,
            'fuzzy_date_amount'::VARCHAR(50) AS match_type,
            0.85::NUMERIC(3,2) AS confidence
        FROM finance.transactions t
        WHERE t.date BETWEEN v_search_date - 1 AND v_search_date + 1
          AND ABS(t.amount) = v_receipt.total_amount
          AND t.receipt_processed = FALSE
          AND t.is_quarantined = FALSE
        ORDER BY ABS(t.date - v_search_date)
        LIMIT 1;
    END IF;

    IF NOT FOUND THEN
        -- Amount-tolerant match: ±1 day + ±1 AED tolerance
        RETURN QUERY
        SELECT
            t.id AS transaction_id,
            'fuzzy_amount'::VARCHAR(50) AS match_type,
            0.75::NUMERIC(3,2) AS confidence
        FROM finance.transactions t
        WHERE t.date BETWEEN v_search_date - 1 AND v_search_date + 1
          AND ABS(ABS(t.amount) - v_receipt.total_amount) <= 1.0
          AND t.receipt_processed = FALSE
          AND t.is_quarantined = FALSE
        ORDER BY ABS(ABS(t.amount) - v_receipt.total_amount), ABS(t.date - v_search_date)
        LIMIT 1;
    END IF;

    IF NOT FOUND THEN
        -- Amount-only match within 3 days
        RETURN QUERY
        SELECT
            t.id AS transaction_id,
            'amount_only'::VARCHAR(50) AS match_type,
            0.60::NUMERIC(3,2) AS confidence
        FROM finance.transactions t
        WHERE t.date BETWEEN v_search_date - 3 AND v_search_date + 3
          AND ABS(t.amount) = v_receipt.total_amount
          AND t.receipt_processed = FALSE
          AND t.is_quarantined = FALSE
        ORDER BY ABS(t.date - v_search_date)
        LIMIT 1;
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION finance.find_matching_transaction(INTEGER) IS
'Find matching transaction for a receipt. Falls back to email_received_at/created_at when receipt_date is NULL. Includes ±1 AED fuzzy amount tier.';

-- ============================================================================
-- 6. REWRITE finalize_receipt() — dedup before INSERT
-- ============================================================================

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
    v_existing_match RECORD;
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
        v_final_total := v_receipt.total_amount;

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
            v_reconciliation_warning := 'Finalized from total_amount only (no line items)';
        END IF;
    ELSE
        v_final_total := v_items_total;
    END IF;

    -- Determine final date (with NULL fallback)
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

    -- Check for existing transaction with this client_id
    SELECT id INTO v_txn_id
    FROM finance.transactions
    WHERE client_id = v_client_id;

    IF v_txn_id IS NULL THEN
        -- DEDUP CHECK: look for existing transaction (e.g. from SMS) that matches
        SELECT t.id INTO v_existing_match
        FROM finance.transactions t
        WHERE t.date BETWEEN v_final_date - 1 AND v_final_date + 1
          AND ABS(ABS(t.amount) - v_final_total) <= 1.0
          AND t.receipt_processed = false
          AND t.is_quarantined = false
          AND (t.is_grocery = true OR t.category IN ('Groceries', 'Restaurant'))
        ORDER BY ABS(ABS(t.amount) - v_final_total), ABS(t.date - v_final_date)
        LIMIT 1;

        IF v_existing_match.id IS NOT NULL THEN
            -- Link receipt to existing transaction instead of creating a duplicate
            v_txn_id := v_existing_match.id;

            UPDATE finance.transactions
            SET receipt_processed = true
            WHERE id = v_txn_id;
        ELSE
            -- No match found — create new transaction
            INSERT INTO finance.transactions (
                date, transaction_at, merchant_name, amount, currency,
                category, is_grocery, client_id, source, notes, receipt_processed
            ) VALUES (
                v_final_date,
                COALESCE(v_receipt.receipt_datetime, v_receipt.email_received_at, v_receipt.created_at),
                v_merchant_name,
                -ABS(v_final_total),
                COALESCE(v_receipt.currency, 'AED'),
                'Groceries', TRUE, v_client_id, 'receipt',
                format('Auto-created from receipt #%s', p_receipt_id),
                TRUE
            )
            RETURNING id INTO v_txn_id;
        END IF;
    END IF;

    -- Update receipt
    UPDATE finance.receipts SET
        total_amount = v_final_total,
        receipt_date = v_final_date,
        linked_transaction_id = v_txn_id,
        link_method = CASE
            WHEN v_existing_match.id IS NOT NULL THEN 'dedup_match'
            ELSE 'auto_finalize'
        END,
        link_confidence = CASE
            WHEN v_existing_match.id IS NOT NULL THEN 0.90
            WHEN v_reconciliation_warning IS NULL THEN 1.00
            ELSE 0.80
        END,
        linked_at = NOW(),
        parsed_at = COALESCE(parsed_at, NOW()),
        parse_status = 'success',
        parse_error = v_reconciliation_warning,
        updated_at = NOW()
    WHERE id = p_receipt_id;

    RETURN jsonb_build_object(
        'status', CASE WHEN v_existing_match.id IS NOT NULL THEN 'linked_existing' ELSE 'finalized' END,
        'receipt_id', p_receipt_id,
        'transaction_id', v_txn_id,
        'total_amount', v_final_total,
        'merchant', v_merchant_name,
        'receipt_date', v_final_date,
        'item_count', v_item_count,
        'client_id', v_client_id,
        'warning', v_reconciliation_warning,
        'dedup_matched', v_existing_match.id IS NOT NULL
    );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION finance.finalize_receipt(INTEGER) IS
'Receipt-first finalization with dedup: checks for existing SMS transaction before creating new one. Uses Groceries category.';

-- ============================================================================
-- 7. UPDATE VIEWS REFERENCING 'Grocery'
-- ============================================================================

-- 7a. v_timeline: add 'Groceries' alongside 'Grocery' in category arrays
DROP VIEW IF EXISTS finance.v_timeline CASCADE;

CREATE VIEW finance.v_timeline AS
WITH sms_events AS (
    SELECT
        sc.received_at,
        sc.canonical_intent,
        sc.merchant,
        sc.amount,
        sc.currency,
        sc.transaction_id,
        sc.created_transaction,
        t.category,
        t.date as transaction_date
    FROM raw.sms_classifications sc
    LEFT JOIN finance.transactions t ON sc.transaction_id = t.id
),
transaction_events AS (
    SELECT
        t.id as transaction_id,
        COALESCE(t.transaction_at, t.date::timestamptz) as event_time,
        t.date,
        t.merchant_name,
        t.amount,
        t.currency,
        t.category,
        CASE
            WHEN t.client_id IS NOT NULL THEN 'webhook'
            WHEN t.external_id LIKE 'SMS%' THEN 'sms'
            ELSE 'receipt'
        END as source
    FROM finance.transactions t
),
sms_only_events AS (
    SELECT
        se.received_at as event_time,
        NULL::date as date,
        se.merchant,
        se.amount,
        se.currency,
        NULL::varchar(50) as category,
        'sms' as source,
        se.canonical_intent,
        NULL::integer as transaction_id
    FROM sms_events se
    WHERE se.created_transaction = false
      AND se.canonical_intent IN ('FIN_TXN_DECLINED', 'FIN_INFO_ONLY', 'FIN_TXN_REFUND')
)
SELECT
    te.event_time,
    te.date,
    EXTRACT(HOUR FROM te.event_time AT TIME ZONE 'Asia/Dubai')::int || ':' ||
        LPAD(EXTRACT(MINUTE FROM te.event_time AT TIME ZONE 'Asia/Dubai')::text, 2, '0') as time,
    CASE
        WHEN te.category IN ('Purchase', 'Food', 'Groceries', 'Transport', 'Shopping', 'Utilities', 'Health', 'ATM', 'Bank Fees')
             AND te.amount < 0 THEN 'bank_tx'
        WHEN te.category IN ('Income', 'Salary', 'Deposit')
             AND te.amount > 0 THEN 'bank_tx'
        WHEN te.category = 'Refund' AND te.amount > 0 THEN 'refund'
        WHEN te.category IN ('Transfer', 'Credit Card Payment') THEN 'info'
        ELSE 'bank_tx'
    END as event_type,
    te.amount,
    te.currency,
    te.merchant_name as merchant,
    te.category,
    te.source,
    CASE
        WHEN te.category IN ('Purchase', 'Food', 'Groceries', 'Transport', 'Shopping', 'Utilities', 'Health', 'ATM', 'Bank Fees', 'Income', 'Salary', 'Deposit', 'Refund') THEN true
        WHEN te.category IN ('Transfer', 'Credit Card Payment') THEN false
        ELSE true
    END as is_actionable,
    te.transaction_id
FROM transaction_events te

UNION ALL

SELECT
    so.event_time,
    so.date,
    EXTRACT(HOUR FROM so.event_time AT TIME ZONE 'Asia/Dubai')::int || ':' ||
        LPAD(EXTRACT(MINUTE FROM so.event_time AT TIME ZONE 'Asia/Dubai')::text, 2, '0') as time,
    CASE
        WHEN so.canonical_intent = 'FIN_TXN_DECLINED' THEN 'info'
        WHEN so.canonical_intent = 'FIN_TXN_REFUND' THEN 'wallet_event'
        WHEN so.canonical_intent = 'FIN_INFO_ONLY' THEN 'info'
        ELSE 'info'
    END as event_type,
    so.amount,
    so.currency,
    so.merchant,
    so.category,
    so.source,
    false as is_actionable,
    so.transaction_id
FROM sms_only_events so

ORDER BY event_time DESC;

COMMENT ON VIEW finance.v_timeline IS 'Unified finance timeline distinguishing bank transactions, refunds, wallet events, and informational messages';

-- 7b. v_inferred_meals: Grocery → Groceries
CREATE OR REPLACE VIEW life.v_inferred_meals AS
WITH
restaurant_meals AS (
    SELECT
        (transaction_at AT TIME ZONE 'Asia/Dubai')::DATE as meal_date,
        (transaction_at AT TIME ZONE 'Asia/Dubai')::TIME as meal_time,
        CASE
            WHEN EXTRACT(HOUR FROM transaction_at AT TIME ZONE 'Asia/Dubai') BETWEEN 6 AND 10 THEN 'breakfast'
            WHEN EXTRACT(HOUR FROM transaction_at AT TIME ZONE 'Asia/Dubai') BETWEEN 11 AND 15 THEN 'lunch'
            WHEN EXTRACT(HOUR FROM transaction_at AT TIME ZONE 'Asia/Dubai') BETWEEN 18 AND 22 THEN 'dinner'
            ELSE 'snack'
        END as meal_type,
        0.9 as confidence,
        'restaurant' as source,
        jsonb_build_object(
            'source', 'restaurant_transaction',
            'merchant', merchant_name,
            'amount', amount,
            'currency', currency
        ) as signals_used
    FROM finance.transactions
    WHERE category = 'Restaurant'
        AND amount < 0
        AND (transaction_at AT TIME ZONE 'Asia/Dubai')::DATE >= CURRENT_DATE - INTERVAL '30 days'
),
home_cooking AS (
    SELECT DISTINCT
        dls.day as meal_date,
        '12:30:00'::TIME as meal_time,
        'lunch' as meal_type,
        0.6 as confidence,
        'home_cooking' as source,
        jsonb_build_object(
            'source', 'home_location',
            'hours_at_home', dls.hours_at_home,
            'tv_hours', COALESCE(dbs.tv_hours, 0),
            'tv_off', COALESCE(dbs.tv_hours, 0) < 0.5
        ) as signals_used
    FROM life.daily_location_summary dls
    LEFT JOIN life.daily_behavioral_summary dbs ON dbs.day = dls.day
    WHERE dls.day >= CURRENT_DATE - INTERVAL '30 days'
        AND dls.hours_at_home >= 0.5
        AND COALESCE(dbs.tv_hours, 0) < 1.0
        AND dls.hours_at_home IS NOT NULL
),
home_dinner AS (
    SELECT DISTINCT
        dls.day as meal_date,
        '19:30:00'::TIME as meal_time,
        'dinner' as meal_type,
        0.6 as confidence,
        'home_cooking' as source,
        jsonb_build_object(
            'source', 'home_location_evening',
            'hours_at_home', dls.hours_at_home,
            'last_arrival', dls.last_arrival
        ) as signals_used
    FROM life.daily_location_summary dls
    WHERE dls.day >= CURRENT_DATE - INTERVAL '30 days'
        AND dls.hours_at_home >= 1.0
        AND dls.last_arrival IS NOT NULL
        AND EXTRACT(HOUR FROM dls.last_arrival AT TIME ZONE 'Asia/Dubai') BETWEEN 17 AND 22
),
grocery_inference AS (
    SELECT DISTINCT
        t.transaction_at::DATE as meal_date,
        '20:00:00'::TIME as meal_time,
        'dinner' as meal_type,
        0.4 as confidence,
        'grocery_purchase' as source,
        jsonb_build_object(
            'source', 'grocery_transaction',
            'merchant', t.merchant_name,
            'amount', t.amount,
            'home_evening', EXISTS (
                SELECT 1 FROM life.daily_location_summary dls
                WHERE dls.day = t.transaction_at::DATE
                    AND dls.hours_at_home > 0
                    AND dls.last_arrival IS NOT NULL
                    AND EXTRACT(HOUR FROM dls.last_arrival AT TIME ZONE 'Asia/Dubai') BETWEEN 18 AND 22
            )
        ) as signals_used
    FROM finance.transactions t
    WHERE t.category = 'Groceries'
        AND t.amount < 0
        AND t.transaction_at::DATE >= CURRENT_DATE - INTERVAL '30 days'
        AND EXISTS (
            SELECT 1 FROM life.daily_location_summary dls
            WHERE dls.day = t.transaction_at::DATE
                AND dls.hours_at_home > 0
        )
)
SELECT
    inferred.meal_date as inferred_at_date,
    inferred.meal_time as inferred_at_time,
    inferred.meal_type,
    inferred.confidence,
    inferred.source as inference_source,
    inferred.signals_used,
    COALESCE(mc.user_action, 'pending') as confirmation_status
FROM (
    SELECT * FROM restaurant_meals
    UNION ALL
    SELECT * FROM home_cooking
    UNION ALL
    SELECT * FROM home_dinner
    UNION ALL
    SELECT * FROM grocery_inference
) inferred
LEFT JOIN life.meal_confirmations mc
    ON mc.inferred_meal_date = inferred.meal_date
    AND mc.inferred_meal_time = inferred.meal_time
WHERE COALESCE(mc.user_action, 'pending') = 'pending'
ORDER BY inferred.meal_date DESC, inferred.meal_time DESC;

-- 7c. v_meal_coverage_gaps: Grocery → Groceries
CREATE OR REPLACE VIEW life.v_meal_coverage_gaps AS
WITH daily_signals AS (
    SELECT
        d.day,
        EXISTS (
            SELECT 1 FROM raw.healthkit_samples h
            WHERE h.start_date::date = d.day
        ) as has_healthkit,
        EXISTS (
            SELECT 1 FROM life.v_inferred_meals m
            WHERE m.inferred_at_date = d.day
        ) as has_inferred_meals,
        EXISTS (
            SELECT 1 FROM finance.transactions t
            WHERE finance.to_business_date(t.transaction_at) = d.day
            AND t.category IN ('Restaurant', 'Groceries')
        ) as has_food_transactions,
        EXISTS (
            SELECT 1 FROM life.meal_confirmations mc
            WHERE mc.inferred_meal_date = d.day
        ) as has_confirmed_meals,
        EXISTS (
            SELECT 1 FROM life.daily_behavioral_summary b
            WHERE b.day = d.day
        ) as has_behavioral_signals
    FROM generate_series(
        CURRENT_DATE - INTERVAL '30 days',
        CURRENT_DATE,
        '1 day'::interval
    ) AS d(day)
)
SELECT
    day,
    has_healthkit,
    has_inferred_meals,
    has_food_transactions,
    has_confirmed_meals,
    has_behavioral_signals,
    CASE
        WHEN has_healthkit AND NOT has_inferred_meals THEN 'healthkit_no_meals'
        ELSE NULL
    END as gap_healthkit_no_meals,
    CASE
        WHEN has_inferred_meals AND NOT has_food_transactions THEN 'meals_no_food_tx'
        ELSE NULL
    END as gap_meals_no_food_tx,
    CASE
        WHEN has_confirmed_meals AND NOT has_behavioral_signals THEN 'confirmed_no_signals'
        ELSE NULL
    END as gap_confirmed_no_signals,
    CASE
        WHEN has_healthkit AND NOT has_inferred_meals THEN 'inference_failure'
        WHEN has_inferred_meals AND NOT has_food_transactions THEN 'missing_context'
        WHEN has_confirmed_meals AND NOT has_behavioral_signals THEN 'signal_loss'
        WHEN has_healthkit OR has_inferred_meals OR has_food_transactions THEN 'partial_data'
        ELSE 'no_meal_data'
    END as gap_status
FROM daily_signals
ORDER BY day DESC;

COMMENT ON VIEW life.v_meal_coverage_gaps IS 'Identifies meal-related data quality issues: HealthKit without meals, meals without transactions, confirmed meals without signals';

-- ============================================================================
-- 8. REFRESH MATERIALIZED DATA
-- ============================================================================

SELECT life.refresh_daily_facts();

-- Refresh financial truth with non-concurrent fallback
DO $$
BEGIN
    PERFORM finance.refresh_financial_truth();
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'refresh_financial_truth failed: %. Refreshing mv_monthly_spend non-concurrently.', SQLERRM;
    REFRESH MATERIALIZED VIEW finance.mv_monthly_spend;
END $$;
