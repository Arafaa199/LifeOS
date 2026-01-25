-- Raw Schema Immutability Tests
-- Run with: psql -U nexus -d nexus -f tests/013_raw_immutability_tests.sql
-- Tests: INSERT-only enforcement on raw.* tables

-- ================================================
-- Test Case 1: INSERT to raw.manual_entries succeeds
-- ================================================
DO $$
DECLARE
    v_id BIGINT;
BEGIN
    INSERT INTO raw.manual_entries (
        entry_type, timestamp, date, payload, source, run_id, client_id
    ) VALUES (
        'expense', NOW(), CURRENT_DATE, '{"test": true}'::jsonb, 'test', gen_random_uuid(), 'test-immutable-001'
    ) RETURNING id INTO v_id;

    IF v_id IS NOT NULL THEN
        RAISE NOTICE 'TEST 1 PASSED: INSERT to raw.manual_entries succeeded (id=%)', v_id;
    ELSE
        RAISE EXCEPTION 'TEST 1 FAILED: INSERT did not return id';
    END IF;
END $$;

-- ================================================
-- Test Case 2: UPDATE to raw.manual_entries BLOCKED
-- ================================================
DO $$
BEGIN
    -- Attempt to update - should fail
    UPDATE raw.manual_entries
    SET payload = '{"modified": true}'::jsonb
    WHERE client_id = 'test-immutable-001';

    -- If we get here, the trigger didn't work
    RAISE EXCEPTION 'TEST 2 FAILED: UPDATE should have been blocked!';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%immutable%' THEN
            RAISE NOTICE 'TEST 2 PASSED: UPDATE blocked with message: %', SQLERRM;
        ELSE
            RAISE EXCEPTION 'TEST 2 FAILED: Unexpected error: %', SQLERRM;
        END IF;
END $$;

-- ================================================
-- Test Case 3: DELETE from raw.manual_entries BLOCKED
-- ================================================
DO $$
BEGIN
    -- Attempt to delete - should fail
    DELETE FROM raw.manual_entries WHERE client_id = 'test-immutable-001';

    -- If we get here, the trigger didn't work
    RAISE EXCEPTION 'TEST 3 FAILED: DELETE should have been blocked!';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%immutable%' THEN
            RAISE NOTICE 'TEST 3 PASSED: DELETE blocked with message: %', SQLERRM;
        ELSE
            RAISE EXCEPTION 'TEST 3 FAILED: Unexpected error: %', SQLERRM;
        END IF;
END $$;

-- ================================================
-- Test Case 4: INSERT to raw.bank_sms succeeds
-- ================================================
DO $$
DECLARE
    v_id BIGINT;
BEGIN
    INSERT INTO raw.bank_sms (
        message_id, sender, body, received_at, source, run_id
    ) VALUES (
        'test-sms-immutable-001', 'TestBank', 'Test SMS body', NOW(), 'test', gen_random_uuid()
    ) RETURNING id INTO v_id;

    IF v_id IS NOT NULL THEN
        RAISE NOTICE 'TEST 4 PASSED: INSERT to raw.bank_sms succeeded (id=%)', v_id;
    ELSE
        RAISE EXCEPTION 'TEST 4 FAILED: INSERT did not return id';
    END IF;
END $$;

-- ================================================
-- Test Case 5: UPDATE to raw.bank_sms BLOCKED
-- ================================================
DO $$
BEGIN
    UPDATE raw.bank_sms SET body = 'Modified body' WHERE message_id = 'test-sms-immutable-001';
    RAISE EXCEPTION 'TEST 5 FAILED: UPDATE should have been blocked!';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%immutable%' THEN
            RAISE NOTICE 'TEST 5 PASSED: UPDATE blocked on raw.bank_sms';
        ELSE
            RAISE EXCEPTION 'TEST 5 FAILED: Unexpected error: %', SQLERRM;
        END IF;
END $$;

-- ================================================
-- Test Case 6: INSERT to raw.healthkit_samples succeeds
-- ================================================
DO $$
DECLARE
    v_id BIGINT;
BEGIN
    INSERT INTO raw.healthkit_samples (
        sample_type, value, unit, start_date, end_date, source_name, source, run_id
    ) VALUES (
        'test_weight', 75.5, 'kg', NOW() - INTERVAL '1 hour', NOW(), 'TestDevice', 'test', gen_random_uuid()
    ) RETURNING id INTO v_id;

    IF v_id IS NOT NULL THEN
        RAISE NOTICE 'TEST 6 PASSED: INSERT to raw.healthkit_samples succeeded (id=%)', v_id;
    ELSE
        RAISE EXCEPTION 'TEST 6 FAILED: INSERT did not return id';
    END IF;

    -- Cleanup (this will fail due to immutability, which is expected)
    -- We skip cleanup for raw tables in tests
END $$;

-- ================================================
-- Test Case 7: UPDATE to raw.healthkit_samples BLOCKED
-- ================================================
DO $$
BEGIN
    UPDATE raw.healthkit_samples SET value = 80.0 WHERE sample_type = 'test_weight';
    RAISE EXCEPTION 'TEST 7 FAILED: UPDATE should have been blocked!';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%immutable%' THEN
            RAISE NOTICE 'TEST 7 PASSED: UPDATE blocked on raw.healthkit_samples';
        ELSE
            RAISE EXCEPTION 'TEST 7 FAILED: Unexpected error: %', SQLERRM;
        END IF;
END $$;

-- ================================================
-- Test Case 8: Verify trigger function exists
-- ================================================
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'raw' AND p.proname = 'prevent_modification'
    ) THEN
        RAISE NOTICE 'TEST 8 PASSED: raw.prevent_modification() function exists';
    ELSE
        RAISE EXCEPTION 'TEST 8 FAILED: raw.prevent_modification() function not found';
    END IF;
END $$;

-- ================================================
-- Note: Test data remains in raw tables (immutable by design)
-- Use truncate with cascade or drop/recreate for cleanup
-- ================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Raw Immutability Tests Complete';
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Test 1: INSERT to raw.manual_entries';
    RAISE NOTICE 'Test 2: UPDATE blocked on raw.manual_entries';
    RAISE NOTICE 'Test 3: DELETE blocked on raw.manual_entries';
    RAISE NOTICE 'Test 4: INSERT to raw.bank_sms';
    RAISE NOTICE 'Test 5: UPDATE blocked on raw.bank_sms';
    RAISE NOTICE 'Test 6: INSERT to raw.healthkit_samples';
    RAISE NOTICE 'Test 7: UPDATE blocked on raw.healthkit_samples';
    RAISE NOTICE 'Test 8: prevent_modification function exists';
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'NOTE: Test data in raw.* tables is immutable';
    RAISE NOTICE 'Use TRUNCATE with superuser for cleanup if needed';
    RAISE NOTICE '==========================================';
END $$;
