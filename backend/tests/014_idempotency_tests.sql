-- Idempotency Tests for Finance Transactions
-- Run with: psql -U nexus -d nexus -f tests/014_idempotency_tests.sql
-- Tests: client_id uniqueness constraint, duplicate handling

-- ================================================
-- Setup: Clean test data
-- ================================================
DO $$
BEGIN
    DELETE FROM finance.transactions WHERE client_id LIKE 'test-idem-%';
    DELETE FROM finance.raw_events WHERE client_id LIKE 'test-idem-%';
    RAISE NOTICE 'Setup: Cleaned existing test-idem-* records';
END $$;

-- ================================================
-- Test Case 1: First INSERT with client_id succeeds
-- ================================================
DO $$
DECLARE
    v_id INTEGER;
    v_client_id VARCHAR := 'test-idem-001';
BEGIN
    INSERT INTO finance.transactions (
        date, amount, currency, merchant_name, client_id, notes
    ) VALUES (
        CURRENT_DATE, -100.00, 'AED', 'Test Merchant', v_client_id, '[TEST] Idempotency first insert'
    ) RETURNING id INTO v_id;

    IF v_id IS NOT NULL THEN
        RAISE NOTICE 'TEST 1 PASSED: First INSERT with client_id succeeded (id=%)', v_id;
    ELSE
        RAISE EXCEPTION 'TEST 1 FAILED: INSERT did not return id';
    END IF;
END $$;

-- ================================================
-- Test Case 2: Duplicate client_id BLOCKED by constraint
-- ================================================
DO $$
DECLARE
    v_id INTEGER;
BEGIN
    -- Attempt duplicate insert - should fail
    INSERT INTO finance.transactions (
        date, amount, currency, merchant_name, client_id, notes
    ) VALUES (
        CURRENT_DATE, -100.00, 'AED', 'Test Merchant', 'test-idem-001', '[TEST] Duplicate attempt'
    ) RETURNING id INTO v_id;

    RAISE EXCEPTION 'TEST 2 FAILED: Duplicate client_id should have been blocked!';
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE 'TEST 2 PASSED: Duplicate client_id blocked by unique constraint';
    WHEN OTHERS THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Unexpected error: %', SQLERRM;
END $$;

-- ================================================
-- Test Case 3: ON CONFLICT DO NOTHING (idempotent upsert)
-- ================================================
DO $$
DECLARE
    v_count_before INTEGER;
    v_count_after INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count_before FROM finance.transactions WHERE client_id = 'test-idem-001';

    -- Use ON CONFLICT to handle duplicate gracefully
    INSERT INTO finance.transactions (
        date, amount, currency, merchant_name, client_id, notes
    ) VALUES (
        CURRENT_DATE, -100.00, 'AED', 'Test Merchant', 'test-idem-001', '[TEST] ON CONFLICT attempt'
    ) ON CONFLICT (client_id) WHERE client_id IS NOT NULL DO NOTHING;

    SELECT COUNT(*) INTO v_count_after FROM finance.transactions WHERE client_id = 'test-idem-001';

    IF v_count_before = v_count_after AND v_count_after = 1 THEN
        RAISE NOTICE 'TEST 3 PASSED: ON CONFLICT DO NOTHING handled duplicate gracefully (count=%)', v_count_after;
    ELSE
        RAISE EXCEPTION 'TEST 3 FAILED: Expected count to remain 1, got before=%, after=%', v_count_before, v_count_after;
    END IF;
END $$;

-- ================================================
-- Test Case 4: NULL client_id allows duplicates (SMS imports)
-- ================================================
DO $$
DECLARE
    v_id1 INTEGER;
    v_id2 INTEGER;
BEGIN
    INSERT INTO finance.transactions (
        date, amount, currency, merchant_name, client_id, notes
    ) VALUES (
        CURRENT_DATE, -50.00, 'AED', 'SMS Merchant', NULL, '[TEST] NULL client_id 1'
    ) RETURNING id INTO v_id1;

    INSERT INTO finance.transactions (
        date, amount, currency, merchant_name, client_id, notes
    ) VALUES (
        CURRENT_DATE, -50.00, 'AED', 'SMS Merchant', NULL, '[TEST] NULL client_id 2'
    ) RETURNING id INTO v_id2;

    IF v_id1 IS NOT NULL AND v_id2 IS NOT NULL AND v_id1 != v_id2 THEN
        RAISE NOTICE 'TEST 4 PASSED: NULL client_id allows multiple inserts (id1=%, id2=%)', v_id1, v_id2;
        -- Cleanup
        DELETE FROM finance.transactions WHERE id IN (v_id1, v_id2);
    ELSE
        RAISE EXCEPTION 'TEST 4 FAILED: NULL client_id should allow duplicates';
    END IF;
END $$;

-- ================================================
-- Test Case 5: Different client_ids are separate records
-- ================================================
DO $$
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO finance.transactions (
        date, amount, currency, merchant_name, client_id, notes
    ) VALUES (
        CURRENT_DATE, -200.00, 'AED', 'Test Merchant 2', 'test-idem-002', '[TEST] Second unique client_id'
    ) RETURNING id INTO v_id;

    IF v_id IS NOT NULL THEN
        RAISE NOTICE 'TEST 5 PASSED: Different client_id creates new record (id=%)', v_id;
    ELSE
        RAISE EXCEPTION 'TEST 5 FAILED: INSERT with new client_id failed';
    END IF;
END $$;

-- ================================================
-- Test Case 6: Verify unique constraint exists
-- ================================================
DO $$
DECLARE
    v_constraint_exists BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'transactions_client_id_unique'
        AND conrelid = 'finance.transactions'::regclass
    ) INTO v_constraint_exists;

    IF v_constraint_exists THEN
        RAISE NOTICE 'TEST 6 PASSED: transactions_client_id_unique constraint exists';
    ELSE
        RAISE EXCEPTION 'TEST 6 FAILED: transactions_client_id_unique constraint not found';
    END IF;
END $$;

-- ================================================
-- Test Case 7: Count constraint violations (verification query)
-- ================================================
DO $$
DECLARE
    v_duplicate_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_duplicate_count
    FROM (
        SELECT client_id, COUNT(*) as cnt
        FROM finance.transactions
        WHERE client_id IS NOT NULL
        GROUP BY client_id
        HAVING COUNT(*) > 1
    ) dups;

    IF v_duplicate_count = 0 THEN
        RAISE NOTICE 'TEST 7 PASSED: No duplicate client_ids in database (0 duplicates)';
    ELSE
        RAISE EXCEPTION 'TEST 7 FAILED: Found % duplicate client_id groups', v_duplicate_count;
    END IF;
END $$;

-- ================================================
-- Cleanup
-- ================================================
DO $$
BEGIN
    DELETE FROM finance.transactions WHERE client_id LIKE 'test-idem-%';
    DELETE FROM finance.transactions WHERE notes LIKE '%[TEST]%';
    RAISE NOTICE 'Cleanup complete';
END $$;

-- ================================================
-- Summary
-- ================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Idempotency Tests Complete';
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Test 1: First INSERT with client_id';
    RAISE NOTICE 'Test 2: Duplicate client_id blocked';
    RAISE NOTICE 'Test 3: ON CONFLICT DO NOTHING works';
    RAISE NOTICE 'Test 4: NULL client_id allows duplicates';
    RAISE NOTICE 'Test 5: Different client_ids are separate';
    RAISE NOTICE 'Test 6: Unique constraint exists';
    RAISE NOTICE 'Test 7: No duplicates in production data';
    RAISE NOTICE '==========================================';
END $$;
