-- Timezone Function Tests
-- Run with: psql -U nexus -d nexus -f tests/011_timezone_tests.sql
-- Tests: finance.to_business_date(), finance.current_business_date(), transaction_at trigger

-- ================================================
-- Test Case 1: Midnight Boundary (20:00 UTC = 00:00 Dubai)
-- ================================================
DO $$
DECLARE
    v_result DATE;
BEGIN
    -- 20:00 UTC on Jan 24 = 00:00 Jan 25 Dubai (next business day)
    v_result := finance.to_business_date('2026-01-24 20:00:00+00'::TIMESTAMPTZ);

    IF v_result = '2026-01-25'::DATE THEN
        RAISE NOTICE 'TEST 1 PASSED: 20:00 UTC correctly maps to 2026-01-25 Dubai';
    ELSE
        RAISE EXCEPTION 'TEST 1 FAILED: Expected 2026-01-25, got %', v_result;
    END IF;
END $$;

-- ================================================
-- Test Case 2: Pre-Midnight (19:59 UTC = 23:59 Dubai)
-- ================================================
DO $$
DECLARE
    v_result DATE;
BEGIN
    -- 19:59 UTC on Jan 24 = 23:59 Jan 24 Dubai (same business day)
    v_result := finance.to_business_date('2026-01-24 19:59:00+00'::TIMESTAMPTZ);

    IF v_result = '2026-01-24'::DATE THEN
        RAISE NOTICE 'TEST 2 PASSED: 19:59 UTC correctly maps to 2026-01-24 Dubai';
    ELSE
        RAISE EXCEPTION 'TEST 2 FAILED: Expected 2026-01-24, got %', v_result;
    END IF;
END $$;

-- ================================================
-- Test Case 3: Midday UTC (12:00 UTC = 16:00 Dubai)
-- ================================================
DO $$
DECLARE
    v_result DATE;
BEGIN
    -- 12:00 UTC on Jan 24 = 16:00 Jan 24 Dubai (same day)
    v_result := finance.to_business_date('2026-01-24 12:00:00+00'::TIMESTAMPTZ);

    IF v_result = '2026-01-24'::DATE THEN
        RAISE NOTICE 'TEST 3 PASSED: 12:00 UTC correctly maps to 2026-01-24 Dubai';
    ELSE
        RAISE EXCEPTION 'TEST 3 FAILED: Expected 2026-01-24, got %', v_result;
    END IF;
END $$;

-- ================================================
-- Test Case 4: Late Night Dubai (00:30 UTC = 04:30 Dubai)
-- ================================================
DO $$
DECLARE
    v_result DATE;
BEGIN
    -- 00:30 UTC on Jan 25 = 04:30 Jan 25 Dubai
    v_result := finance.to_business_date('2026-01-25 00:30:00+00'::TIMESTAMPTZ);

    IF v_result = '2026-01-25'::DATE THEN
        RAISE NOTICE 'TEST 4 PASSED: 00:30 UTC correctly maps to 2026-01-25 Dubai';
    ELSE
        RAISE EXCEPTION 'TEST 4 FAILED: Expected 2026-01-25, got %', v_result;
    END IF;
END $$;

-- ================================================
-- Test Case 5: Different Timezone Input (Dubai local)
-- ================================================
DO $$
DECLARE
    v_result DATE;
BEGIN
    -- Input as Dubai time directly
    v_result := finance.to_business_date('2026-01-24 10:00:00+04'::TIMESTAMPTZ);

    IF v_result = '2026-01-24'::DATE THEN
        RAISE NOTICE 'TEST 5 PASSED: Dubai timezone input correctly maps to 2026-01-24';
    ELSE
        RAISE EXCEPTION 'TEST 5 FAILED: Expected 2026-01-24, got %', v_result;
    END IF;
END $$;

-- ================================================
-- Test Case 6: current_business_date() returns today's Dubai date
-- ================================================
DO $$
DECLARE
    v_result DATE;
    v_expected DATE;
BEGIN
    v_result := finance.current_business_date();
    v_expected := (NOW() AT TIME ZONE 'Asia/Dubai')::DATE;

    IF v_result = v_expected THEN
        RAISE NOTICE 'TEST 6 PASSED: current_business_date() returns correct Dubai date: %', v_result;
    ELSE
        RAISE EXCEPTION 'TEST 6 FAILED: Expected %, got %', v_expected, v_result;
    END IF;
END $$;

-- ================================================
-- Test Case 7: Auto-set transaction_at trigger
-- ================================================
DO $$
DECLARE
    v_tx_id INTEGER;
    v_transaction_at TIMESTAMPTZ;
BEGIN
    -- Insert without transaction_at - should auto-set
    INSERT INTO finance.transactions (
        date, amount, currency, merchant_name, notes
    ) VALUES (
        CURRENT_DATE, -50.00, 'AED', 'TEST MERCHANT', '[TEST] Auto transaction_at'
    ) RETURNING id, transaction_at INTO v_tx_id, v_transaction_at;

    IF v_transaction_at IS NOT NULL AND v_transaction_at >= NOW() - INTERVAL '5 seconds' THEN
        RAISE NOTICE 'TEST 7 PASSED: transaction_at auto-set to %', v_transaction_at;
    ELSE
        RAISE EXCEPTION 'TEST 7 FAILED: transaction_at not auto-set or invalid. Got: %', v_transaction_at;
    END IF;

    -- Cleanup
    DELETE FROM finance.transactions WHERE id = v_tx_id;
END $$;

-- ================================================
-- Test Case 8: Explicit transaction_at preserved
-- ================================================
DO $$
DECLARE
    v_tx_id INTEGER;
    v_transaction_at TIMESTAMPTZ;
    v_expected TIMESTAMPTZ := '2026-01-15 14:30:00+04'::TIMESTAMPTZ;
BEGIN
    -- Insert with explicit transaction_at
    INSERT INTO finance.transactions (
        date, amount, currency, merchant_name, notes, transaction_at
    ) VALUES (
        '2026-01-15'::DATE, -100.00, 'AED', 'TEST EXPLICIT', '[TEST] Explicit transaction_at', v_expected
    ) RETURNING id, transaction_at INTO v_tx_id, v_transaction_at;

    IF v_transaction_at = v_expected THEN
        RAISE NOTICE 'TEST 8 PASSED: Explicit transaction_at preserved: %', v_transaction_at;
    ELSE
        RAISE EXCEPTION 'TEST 8 FAILED: Expected %, got %', v_expected, v_transaction_at;
    END IF;

    -- Cleanup
    DELETE FROM finance.transactions WHERE id = v_tx_id;
END $$;

-- ================================================
-- Summary
-- ================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Timezone Tests Complete';
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Test 1: Midnight boundary (20:00 UTC = Jan 25)';
    RAISE NOTICE 'Test 2: Pre-midnight (19:59 UTC = Jan 24)';
    RAISE NOTICE 'Test 3: Midday UTC mapping';
    RAISE NOTICE 'Test 4: Late night Dubai mapping';
    RAISE NOTICE 'Test 5: Dubai timezone input handling';
    RAISE NOTICE 'Test 6: current_business_date() function';
    RAISE NOTICE 'Test 7: Auto-set transaction_at trigger';
    RAISE NOTICE 'Test 8: Explicit transaction_at preserved';
    RAISE NOTICE '==========================================';
END $$;
