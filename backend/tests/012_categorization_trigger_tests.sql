-- Categorization Trigger Tests
-- Run with: psql -U nexus -d nexus -f tests/012_categorization_trigger_tests.sql
-- Tests: finance.categorize_transaction() trigger behavior

-- ================================================
-- Setup: Ensure test rules exist
-- ================================================
DO $$
BEGIN
    -- Clean up any existing test data
    DELETE FROM finance.transactions WHERE notes LIKE '%[TEST-CAT]%';

    -- Ensure test rules exist (won't duplicate due to ON CONFLICT)
    INSERT INTO finance.merchant_rules (merchant_pattern, category, subcategory, priority, confidence, is_active, notes)
    VALUES
        ('%CARREFOUR%', 'Grocery', NULL, 70, 100, true, '[TEST] Carrefour rule'),
        ('%SALARY%', 'Salary', NULL, 100, 100, true, '[TEST] Salary rule'),
        ('%DEWA%', 'Utilities', 'Electricity', 80, 100, true, '[TEST] DEWA rule'),
        ('%UBER%', 'Transport', 'Rideshare', 60, 95, true, '[TEST] Uber rule')
    ON CONFLICT DO NOTHING;

    RAISE NOTICE 'Setup complete - test rules created';
END $$;

-- ================================================
-- Test Case 1: Basic category assignment (CARREFOUR -> Grocery)
-- ================================================
DO $$
DECLARE
    v_tx_id INTEGER;
    v_category VARCHAR;
    v_match_reason VARCHAR;
    v_match_confidence INTEGER;
BEGIN
    INSERT INTO finance.transactions (
        date, amount, currency, merchant_name, merchant_name_clean, notes
    ) VALUES (
        CURRENT_DATE, -250.00, 'AED', 'CARREFOUR CITY CENTER', 'CARREFOUR CITY CENTER', '[TEST-CAT] Grocery test'
    ) RETURNING id INTO v_tx_id;

    SELECT category, match_reason, match_confidence
    INTO v_category, v_match_reason, v_match_confidence
    FROM finance.transactions WHERE id = v_tx_id;

    IF v_category = 'Grocery' AND v_match_reason LIKE 'rule:%' THEN
        RAISE NOTICE 'TEST 1 PASSED: CARREFOUR -> Grocery (reason: %, confidence: %)', v_match_reason, v_match_confidence;
    ELSE
        RAISE EXCEPTION 'TEST 1 FAILED: Expected Grocery, got % (reason: %)', v_category, v_match_reason;
    END IF;

    DELETE FROM finance.transactions WHERE id = v_tx_id;
END $$;

-- ================================================
-- Test Case 2: Subcategory assignment (DEWA -> Utilities/Electricity)
-- ================================================
DO $$
DECLARE
    v_tx_id INTEGER;
    v_category VARCHAR;
    v_subcategory VARCHAR;
BEGIN
    INSERT INTO finance.transactions (
        date, amount, currency, merchant_name, merchant_name_clean, notes
    ) VALUES (
        CURRENT_DATE, -450.00, 'AED', 'DEWA BILL PAY', 'DEWA BILL PAY', '[TEST-CAT] Utility test'
    ) RETURNING id INTO v_tx_id;

    SELECT category, subcategory
    INTO v_category, v_subcategory
    FROM finance.transactions WHERE id = v_tx_id;

    IF v_category = 'Utilities' AND v_subcategory = 'Electricity' THEN
        RAISE NOTICE 'TEST 2 PASSED: DEWA -> Utilities/Electricity';
    ELSE
        RAISE EXCEPTION 'TEST 2 FAILED: Expected Utilities/Electricity, got %/%', v_category, v_subcategory;
    END IF;

    DELETE FROM finance.transactions WHERE id = v_tx_id;
END $$;

-- ================================================
-- Test Case 3: Unknown merchant -> Uncategorized
-- ================================================
DO $$
DECLARE
    v_tx_id INTEGER;
    v_category VARCHAR;
    v_match_reason VARCHAR;
BEGIN
    INSERT INTO finance.transactions (
        date, amount, currency, merchant_name, merchant_name_clean, notes
    ) VALUES (
        CURRENT_DATE, -99.00, 'AED', 'RANDOM_UNKNOWN_SHOP_XYZ', 'RANDOM_UNKNOWN_SHOP_XYZ', '[TEST-CAT] Unknown test'
    ) RETURNING id INTO v_tx_id;

    SELECT category, match_reason
    INTO v_category, v_match_reason
    FROM finance.transactions WHERE id = v_tx_id;

    IF v_category = 'Uncategorized' AND v_match_reason = 'no_match' THEN
        RAISE NOTICE 'TEST 3 PASSED: Unknown merchant -> Uncategorized (no_match)';
    ELSE
        RAISE EXCEPTION 'TEST 3 FAILED: Expected Uncategorized/no_match, got %/%', v_category, v_match_reason;
    END IF;

    DELETE FROM finance.transactions WHERE id = v_tx_id;
END $$;

-- ================================================
-- Test Case 4: Pre-categorized transaction not overwritten
-- ================================================
DO $$
DECLARE
    v_tx_id INTEGER;
    v_category VARCHAR;
BEGIN
    INSERT INTO finance.transactions (
        date, amount, currency, merchant_name, merchant_name_clean, category, notes
    ) VALUES (
        CURRENT_DATE, -150.00, 'AED', 'CARREFOUR SPECIAL', 'CARREFOUR SPECIAL', 'Shopping', '[TEST-CAT] Pre-categorized'
    ) RETURNING id INTO v_tx_id;

    SELECT category INTO v_category FROM finance.transactions WHERE id = v_tx_id;

    IF v_category = 'Shopping' THEN
        RAISE NOTICE 'TEST 4 PASSED: Pre-categorized Shopping preserved (not overwritten to Grocery)';
    ELSE
        RAISE EXCEPTION 'TEST 4 FAILED: Expected Shopping, got % (should not overwrite)', v_category;
    END IF;

    DELETE FROM finance.transactions WHERE id = v_tx_id;
END $$;

-- ================================================
-- Test Case 5: Uncategorized CAN be overwritten
-- ================================================
DO $$
DECLARE
    v_tx_id INTEGER;
    v_category VARCHAR;
BEGIN
    -- Insert with Uncategorized
    INSERT INTO finance.transactions (
        date, amount, currency, merchant_name, merchant_name_clean, category, notes
    ) VALUES (
        CURRENT_DATE, -75.00, 'AED', 'UBER TRIP', 'UBER TRIP', 'Uncategorized', '[TEST-CAT] Uncategorized override'
    ) RETURNING id INTO v_tx_id;

    SELECT category INTO v_category FROM finance.transactions WHERE id = v_tx_id;

    IF v_category = 'Transport' THEN
        RAISE NOTICE 'TEST 5 PASSED: Uncategorized overwritten to Transport';
    ELSE
        RAISE EXCEPTION 'TEST 5 FAILED: Expected Transport, got % (Uncategorized should be overwritten)', v_category;
    END IF;

    DELETE FROM finance.transactions WHERE id = v_tx_id;
END $$;

-- ================================================
-- Test Case 6: Case-insensitive matching
-- ================================================
DO $$
DECLARE
    v_tx_id INTEGER;
    v_category VARCHAR;
BEGIN
    INSERT INTO finance.transactions (
        date, amount, currency, merchant_name, merchant_name_clean, notes
    ) VALUES (
        CURRENT_DATE, -45.00, 'AED', 'uber trip dubai', 'uber trip dubai', '[TEST-CAT] Lowercase test'
    ) RETURNING id INTO v_tx_id;

    SELECT category INTO v_category FROM finance.transactions WHERE id = v_tx_id;

    IF v_category = 'Transport' THEN
        RAISE NOTICE 'TEST 6 PASSED: Lowercase "uber" matched to Transport';
    ELSE
        RAISE EXCEPTION 'TEST 6 FAILED: Expected Transport, got %', v_category;
    END IF;

    DELETE FROM finance.transactions WHERE id = v_tx_id;
END $$;

-- ================================================
-- Test Case 7: match_rule_id is set correctly
-- ================================================
DO $$
DECLARE
    v_tx_id INTEGER;
    v_match_rule_id INTEGER;
BEGIN
    INSERT INTO finance.transactions (
        date, amount, currency, merchant_name, merchant_name_clean, notes
    ) VALUES (
        CURRENT_DATE, -100.00, 'AED', 'CARREFOUR MALL', 'CARREFOUR MALL', '[TEST-CAT] Rule ID test'
    ) RETURNING id INTO v_tx_id;

    SELECT match_rule_id INTO v_match_rule_id FROM finance.transactions WHERE id = v_tx_id;

    IF v_match_rule_id IS NOT NULL THEN
        -- Verify the rule exists
        IF EXISTS (SELECT 1 FROM finance.merchant_rules WHERE id = v_match_rule_id) THEN
            RAISE NOTICE 'TEST 7 PASSED: match_rule_id % is valid', v_match_rule_id;
        ELSE
            RAISE EXCEPTION 'TEST 7 FAILED: match_rule_id % does not exist', v_match_rule_id;
        END IF;
    ELSE
        RAISE EXCEPTION 'TEST 7 FAILED: match_rule_id is NULL';
    END IF;

    DELETE FROM finance.transactions WHERE id = v_tx_id;
END $$;

-- ================================================
-- Cleanup test rules
-- ================================================
DO $$
BEGIN
    DELETE FROM finance.merchant_rules WHERE notes LIKE '[TEST]%';
    DELETE FROM finance.transactions WHERE notes LIKE '%[TEST-CAT]%';
    RAISE NOTICE 'Cleanup complete';
END $$;

-- ================================================
-- Summary
-- ================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Categorization Trigger Tests Complete';
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Test 1: CARREFOUR -> Grocery';
    RAISE NOTICE 'Test 2: DEWA -> Utilities/Electricity';
    RAISE NOTICE 'Test 3: Unknown -> Uncategorized';
    RAISE NOTICE 'Test 4: Pre-categorized not overwritten';
    RAISE NOTICE 'Test 5: Uncategorized CAN be overwritten';
    RAISE NOTICE 'Test 6: Case-insensitive matching';
    RAISE NOTICE 'Test 7: match_rule_id populated correctly';
    RAISE NOTICE '==========================================';
END $$;
