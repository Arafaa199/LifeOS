-- Migration 094 Reliability Tests
-- Run with: psql -U nexus -d nexus -f tests/094_reliability_tests.sql

-- ================================================
-- Test 1: ops.trigger_errors table exists
-- ================================================
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'ops' AND table_name = 'trigger_errors'
    ) THEN
        RAISE NOTICE 'TEST 1 PASSED: ops.trigger_errors table exists';
    ELSE
        RAISE WARNING 'TEST 1 FAILED: ops.trigger_errors table does not exist';
    END IF;
END $$;

-- ================================================
-- Test 2: life.refresh_all() function exists and is callable
-- ================================================
DO $$
DECLARE
    v_result JSONB;
BEGIN
    v_result := life.refresh_all(1, 'test_094');
    IF v_result->>'refreshed_days' IS NOT NULL THEN
        RAISE NOTICE 'TEST 2 PASSED: life.refresh_all() returned: %', v_result;
    ELSE
        RAISE WARNING 'TEST 2 FAILED: life.refresh_all() returned unexpected result: %', v_result;
    END IF;
END $$;

-- ================================================
-- Test 3: life.refresh_all() is idempotent (call twice, no errors)
-- ================================================
DO $$
DECLARE
    v_r1 JSONB;
    v_r2 JSONB;
BEGIN
    v_r1 := life.refresh_all(1, 'test_idem_1');
    v_r2 := life.refresh_all(1, 'test_idem_2');
    IF (v_r1->>'errors')::int = 0 AND (v_r2->>'errors')::int = 0 THEN
        RAISE NOTICE 'TEST 3 PASSED: refresh_all idempotent, 0 errors on both calls';
    ELSE
        RAISE WARNING 'TEST 3 FAILED: errors on repeated calls. R1: %, R2: %', v_r1, v_r2;
    END IF;
END $$;

-- ================================================
-- Test 4: HealthKit weight trigger exists on health.metrics
-- ================================================
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'trg_feed_healthkit_metrics'
    ) THEN
        RAISE NOTICE 'TEST 4 PASSED: trg_feed_healthkit_metrics trigger exists';
    ELSE
        RAISE WARNING 'TEST 4 FAILED: trg_feed_healthkit_metrics trigger missing';
    END IF;
END $$;

-- ================================================
-- Test 5: weight source in feed_status_live
-- ================================================
DO $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM life.feed_status_live
    WHERE source = 'weight';

    IF v_count = 1 THEN
        RAISE NOTICE 'TEST 5 PASSED: weight source exists in feed_status_live';
    ELSE
        RAISE WARNING 'TEST 5 FAILED: weight source not in feed_status_live (count=%)', v_count;
    END IF;
END $$;

-- ================================================
-- Test 6: Propagation triggers have error logging (not silent swallow)
-- Verify by checking function source contains ops.trigger_errors
-- ================================================
DO $$
DECLARE
    v_recovery_src TEXT;
    v_sleep_src TEXT;
    v_strain_src TEXT;
    v_pass BOOLEAN := TRUE;
BEGIN
    SELECT prosrc INTO v_recovery_src
    FROM pg_proc WHERE proname = 'propagate_whoop_recovery' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'health');

    SELECT prosrc INTO v_sleep_src
    FROM pg_proc WHERE proname = 'propagate_whoop_sleep' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'health');

    SELECT prosrc INTO v_strain_src
    FROM pg_proc WHERE proname = 'propagate_whoop_strain' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'health');

    IF v_recovery_src NOT LIKE '%ops.trigger_errors%' THEN
        RAISE NOTICE '  propagate_whoop_recovery missing error logging';
        v_pass := FALSE;
    END IF;
    IF v_sleep_src NOT LIKE '%ops.trigger_errors%' THEN
        RAISE NOTICE '  propagate_whoop_sleep missing error logging';
        v_pass := FALSE;
    END IF;
    IF v_strain_src NOT LIKE '%ops.trigger_errors%' THEN
        RAISE NOTICE '  propagate_whoop_strain missing error logging';
        v_pass := FALSE;
    END IF;

    IF v_pass THEN
        RAISE NOTICE 'TEST 6 PASSED: All propagation triggers have error logging to ops.trigger_errors';
    ELSE
        RAISE WARNING 'TEST 6 FAILED: Some propagation triggers missing error logging';
    END IF;
END $$;

-- ================================================
-- Test 7: get_payload() auto-refresh checks finance + weight
-- Verify function source references health.metrics and finance.transactions
-- ================================================
DO $$
DECLARE
    v_src TEXT;
    v_pass BOOLEAN := TRUE;
BEGIN
    SELECT prosrc INTO v_src
    FROM pg_proc WHERE proname = 'get_payload' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'dashboard');

    IF v_src NOT LIKE '%health.metrics%' THEN
        RAISE NOTICE '  get_payload missing health.metrics check';
        v_pass := FALSE;
    END IF;
    IF v_src NOT LIKE '%finance.transactions%' THEN
        RAISE NOTICE '  get_payload missing finance.transactions check';
        v_pass := FALSE;
    END IF;

    IF v_pass THEN
        RAISE NOTICE 'TEST 7 PASSED: get_payload() checks health.metrics and finance.transactions for freshness';
    ELSE
        RAISE WARNING 'TEST 7 FAILED: get_payload() missing expanded source checks';
    END IF;
END $$;

-- ================================================
-- Test 8: ops.trigger_errors is empty (no errors from migration)
-- ================================================
DO $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM ops.trigger_errors;
    IF v_count = 0 THEN
        RAISE NOTICE 'TEST 8 PASSED: ops.trigger_errors is empty (no trigger failures)';
    ELSE
        RAISE WARNING 'TEST 8 FAILED: ops.trigger_errors has % rows — check for issues', v_count;
    END IF;
END $$;

-- ================================================
-- Test 9: Regression — existing 093 tests still pass
-- Spend total matches direct query
-- ================================================
DO $$
DECLARE
    v_payload JSONB;
    v_payload_spend NUMERIC;
    v_direct_spend NUMERIC;
    v_today DATE;
BEGIN
    v_today := (current_date AT TIME ZONE 'Asia/Dubai')::date;
    v_payload := dashboard.get_payload();
    v_payload_spend := COALESCE((v_payload->'today_facts'->>'spend_total')::numeric, 0);

    SELECT COALESCE(SUM(ABS(amount)), 0) INTO v_direct_spend
    FROM finance.transactions
    WHERE (transaction_at AT TIME ZONE 'Asia/Dubai')::date = v_today
      AND amount < 0;

    IF ABS(v_payload_spend - v_direct_spend) < 0.01 THEN
        RAISE NOTICE 'TEST 9 PASSED: Spend totals match (payload=%, direct=%)', v_payload_spend, v_direct_spend;
    ELSE
        RAISE WARNING 'TEST 9 FAILED: Spend mismatch (payload=%, direct=%, delta=%)',
            v_payload_spend, v_direct_spend, v_payload_spend - v_direct_spend;
    END IF;
END $$;

-- ================================================
-- Test 10: Regression — payload idempotency
-- ================================================
DO $$
DECLARE
    v_p1 JSONB;
    v_p2 JSONB;
    v_spend1 NUMERIC;
    v_spend2 NUMERIC;
BEGIN
    v_p1 := dashboard.get_payload();
    v_p2 := dashboard.get_payload();

    v_spend1 := COALESCE((v_p1->'today_facts'->>'spend_total')::numeric, 0);
    v_spend2 := COALESCE((v_p2->'today_facts'->>'spend_total')::numeric, 0);

    IF v_spend1 = v_spend2 THEN
        RAISE NOTICE 'TEST 10 PASSED: Payload idempotent (spend=%)', v_spend1;
    ELSE
        RAISE WARNING 'TEST 10 FAILED: Payload not idempotent (call1=%, call2=%)', v_spend1, v_spend2;
    END IF;
END $$;

-- ================================================
-- Test 11: Regression — schema version still 5
-- ================================================
DO $$
DECLARE
    v_payload JSONB;
    v_version INTEGER;
BEGIN
    v_payload := dashboard.get_payload();
    v_version := (v_payload->'meta'->>'schema_version')::integer;

    IF v_version = 5 THEN
        RAISE NOTICE 'TEST 11 PASSED: Schema version is 5';
    ELSE
        RAISE WARNING 'TEST 11 FAILED: Schema version is % (expected 5)', v_version;
    END IF;
END $$;

-- ================================================
-- Test 12: Regression — ISO8601 timestamps in feed_status
-- ================================================
DO $$
DECLARE
    v_payload JSONB;
    v_feed JSONB;
    v_last_sync TEXT;
    v_bad_count INTEGER := 0;
    v_total INTEGER := 0;
BEGIN
    v_payload := dashboard.get_payload();

    FOR v_feed IN SELECT jsonb_array_elements(v_payload->'feed_status')
    LOOP
        v_total := v_total + 1;
        v_last_sync := v_feed->>'last_sync';
        IF v_last_sync IS NOT NULL AND v_last_sync !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' THEN
            v_bad_count := v_bad_count + 1;
            RAISE NOTICE '  Bad ISO8601 in feed %: "%"', v_feed->>'feed', v_last_sync;
        END IF;
    END LOOP;

    IF v_bad_count = 0 THEN
        RAISE NOTICE 'TEST 12 PASSED: All % feed_status last_sync values are ISO8601', v_total;
    ELSE
        RAISE WARNING 'TEST 12 FAILED: % of % feed_status entries have non-ISO8601 timestamps', v_bad_count, v_total;
    END IF;
END $$;
