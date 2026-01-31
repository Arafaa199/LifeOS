-- Domain Status & Freshness Fix Tests (Migration 093)
-- Run with: psql -U nexus -d nexus -f tests/093_domains_status_tests.sql
-- Tests: v_domains_status view, ISO8601 timestamps, get_payload() domains_status,
--        aggregate replay safety (finance totals, feed counts)

-- ================================================
-- Test Case 1: ops.v_domains_status returns rows for health, finance, whoop
-- ================================================
DO $$
DECLARE
    v_count INTEGER;
    v_domains TEXT;
BEGIN
    SELECT COUNT(*), string_agg(domain, ', ' ORDER BY domain)
    INTO v_count, v_domains
    FROM ops.v_domains_status;

    IF v_count >= 3 THEN
        RAISE NOTICE 'TEST 1 PASSED: v_domains_status returns % rows: %', v_count, v_domains;
    ELSE
        RAISE WARNING 'TEST 1 FAILED: Expected >= 3 rows, got %. Domains: %', v_count, v_domains;
    END IF;
END $$;

-- ================================================
-- Test Case 2: v_domains_status.status is one of healthy/stale/critical
-- ================================================
DO $$
DECLARE
    v_bad_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_bad_count
    FROM ops.v_domains_status
    WHERE status NOT IN ('healthy', 'stale', 'critical');

    IF v_bad_count = 0 THEN
        RAISE NOTICE 'TEST 2 PASSED: All domain statuses are valid (healthy/stale/critical)';
    ELSE
        RAISE WARNING 'TEST 2 FAILED: % domains have invalid status values', v_bad_count;
    END IF;
END $$;

-- ================================================
-- Test Case 3: data_freshness.health.last_sync is valid ISO8601
-- ================================================
DO $$
DECLARE
    v_payload JSONB;
    v_last_sync TEXT;
BEGIN
    v_payload := dashboard.get_payload();
    v_last_sync := v_payload->'data_freshness'->'health'->>'last_sync';

    IF v_last_sync IS NULL THEN
        RAISE NOTICE 'TEST 3 SKIPPED: No health last_sync (no health data in DB)';
    ELSIF v_last_sync ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' THEN
        RAISE NOTICE 'TEST 3 PASSED: health.last_sync is ISO8601: %', v_last_sync;
    ELSE
        RAISE WARNING 'TEST 3 FAILED: health.last_sync is not ISO8601: "%"', v_last_sync;
    END IF;
END $$;

-- ================================================
-- Test Case 4: data_freshness.finance.last_sync is valid ISO8601
-- ================================================
DO $$
DECLARE
    v_payload JSONB;
    v_last_sync TEXT;
BEGIN
    v_payload := dashboard.get_payload();
    v_last_sync := v_payload->'data_freshness'->'finance'->>'last_sync';

    IF v_last_sync IS NULL THEN
        RAISE NOTICE 'TEST 4 SKIPPED: No finance last_sync (no transactions in DB)';
    ELSIF v_last_sync ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' THEN
        RAISE NOTICE 'TEST 4 PASSED: finance.last_sync is ISO8601: %', v_last_sync;
    ELSE
        RAISE WARNING 'TEST 4 FAILED: finance.last_sync is not ISO8601: "%"', v_last_sync;
    END IF;
END $$;

-- ================================================
-- Test Case 5: get_payload() includes domains_status key with >= 3 entries
-- ================================================
DO $$
DECLARE
    v_payload JSONB;
    v_domains_status JSONB;
    v_count INTEGER;
BEGIN
    v_payload := dashboard.get_payload();
    v_domains_status := v_payload->'domains_status';

    IF v_domains_status IS NULL THEN
        RAISE WARNING 'TEST 5 FAILED: get_payload() missing domains_status key';
    ELSE
        v_count := jsonb_array_length(v_domains_status);
        IF v_count >= 3 THEN
            RAISE NOTICE 'TEST 5 PASSED: domains_status has % entries', v_count;
        ELSE
            RAISE WARNING 'TEST 5 FAILED: domains_status has only % entries (expected >= 3)', v_count;
        END IF;
    END IF;
END $$;

-- ================================================
-- Test Case 6: All feed_status last_sync values in payload are ISO8601
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
            RAISE NOTICE '  Bad format in feed %: "%"', v_feed->>'feed', v_last_sync;
        END IF;
    END LOOP;

    IF v_bad_count = 0 THEN
        RAISE NOTICE 'TEST 6 PASSED: All % feed_status last_sync values are ISO8601 (or null)', v_total;
    ELSE
        RAISE WARNING 'TEST 6 FAILED: % of % feed_status entries have non-ISO8601 last_sync', v_bad_count, v_total;
    END IF;
END $$;

-- ================================================
-- Test Case 7: Schema version bumped to 5
-- ================================================
DO $$
DECLARE
    v_payload JSONB;
    v_version INTEGER;
BEGIN
    v_payload := dashboard.get_payload();
    v_version := (v_payload->'meta'->>'schema_version')::integer;

    IF v_version = 5 THEN
        RAISE NOTICE 'TEST 7 PASSED: Schema version is 5';
    ELSE
        RAISE WARNING 'TEST 7 FAILED: Schema version is % (expected 5)', v_version;
    END IF;
END $$;

-- ================================================
-- Test Case 8: Finance aggregate replay — total spend matches direct query
-- Compares payload spend_total against SUM from finance.transactions for today
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
        RAISE NOTICE 'TEST 8 PASSED: Spend totals match. Payload: %, Direct: %', v_payload_spend, v_direct_spend;
    ELSE
        RAISE WARNING 'TEST 8 FAILED: Spend mismatch. Payload: %, Direct query: %, Delta: %',
            v_payload_spend, v_direct_spend, v_payload_spend - v_direct_spend;
    END IF;
END $$;

-- ================================================
-- Test Case 9: Finance aggregate replay — transaction count matches
-- ================================================
DO $$
DECLARE
    v_payload JSONB;
    v_payload_count INTEGER;
    v_direct_count INTEGER;
    v_today DATE;
BEGIN
    v_today := (current_date AT TIME ZONE 'Asia/Dubai')::date;
    v_payload := dashboard.get_payload();
    v_payload_count := COALESCE((v_payload->'today_facts'->>'transaction_count')::integer, 0);

    SELECT COUNT(*) INTO v_direct_count
    FROM finance.transactions
    WHERE (transaction_at AT TIME ZONE 'Asia/Dubai')::date = v_today;

    IF v_payload_count = v_direct_count THEN
        RAISE NOTICE 'TEST 9 PASSED: Transaction counts match: %', v_payload_count;
    ELSE
        RAISE WARNING 'TEST 9 FAILED: Count mismatch. Payload: %, Direct: %', v_payload_count, v_direct_count;
    END IF;
END $$;

-- ================================================
-- Test Case 10: Feed status total_records matches direct counts
-- Ensures migration didn't alter feed_status view behavior
-- ================================================
DO $$
DECLARE
    v_feed_count INTEGER;
    v_direct_count INTEGER;
    v_feed_name TEXT;
    v_all_pass BOOLEAN := true;
BEGIN
    -- Check whoop_recovery
    SELECT total_records INTO v_feed_count FROM ops.feed_status WHERE feed = 'whoop_recovery';
    SELECT COUNT(*) INTO v_direct_count FROM health.whoop_recovery;
    IF COALESCE(v_feed_count, 0) != v_direct_count THEN
        RAISE NOTICE '  whoop_recovery: feed_status=%, direct=% MISMATCH', v_feed_count, v_direct_count;
        v_all_pass := false;
    END IF;

    -- Check transactions
    SELECT total_records INTO v_feed_count FROM ops.feed_status WHERE feed = 'transactions';
    SELECT COUNT(*) INTO v_direct_count FROM finance.transactions;
    IF COALESCE(v_feed_count, 0) != v_direct_count THEN
        RAISE NOTICE '  transactions: feed_status=%, direct=% MISMATCH', v_feed_count, v_direct_count;
        v_all_pass := false;
    END IF;

    IF v_all_pass THEN
        RAISE NOTICE 'TEST 10 PASSED: feed_status total_records match direct table counts';
    ELSE
        RAISE WARNING 'TEST 10 FAILED: feed_status total_records do not match direct counts (see above)';
    END IF;
END $$;

-- ================================================
-- Test Case 11: domains_status contract shape validation
-- Each entry must have: domain (text), status (text), as_of (text), last_success (text|null), last_error (text|null)
-- ================================================
DO $$
DECLARE
    v_payload JSONB;
    v_entry JSONB;
    v_bad_count INTEGER := 0;
BEGIN
    v_payload := dashboard.get_payload();

    FOR v_entry IN SELECT jsonb_array_elements(v_payload->'domains_status')
    LOOP
        IF v_entry->>'domain' IS NULL OR v_entry->>'status' IS NULL OR v_entry->>'as_of' IS NULL THEN
            v_bad_count := v_bad_count + 1;
            RAISE NOTICE '  Invalid entry: %', v_entry;
        END IF;
    END LOOP;

    IF v_bad_count = 0 THEN
        RAISE NOTICE 'TEST 11 PASSED: All domains_status entries have required fields (domain, status, as_of)';
    ELSE
        RAISE WARNING 'TEST 11 FAILED: % entries missing required fields', v_bad_count;
    END IF;
END $$;

-- ================================================
-- Test Case 12: Payload idempotency — calling get_payload() twice returns same aggregates
-- ================================================
DO $$
DECLARE
    v_p1 JSONB;
    v_p2 JSONB;
    v_spend1 NUMERIC;
    v_spend2 NUMERIC;
    v_count1 INTEGER;
    v_count2 INTEGER;
BEGIN
    v_p1 := dashboard.get_payload();
    v_p2 := dashboard.get_payload();

    v_spend1 := COALESCE((v_p1->'today_facts'->>'spend_total')::numeric, 0);
    v_spend2 := COALESCE((v_p2->'today_facts'->>'spend_total')::numeric, 0);
    v_count1 := COALESCE((v_p1->'today_facts'->>'transaction_count')::integer, 0);
    v_count2 := COALESCE((v_p2->'today_facts'->>'transaction_count')::integer, 0);

    IF v_spend1 = v_spend2 AND v_count1 = v_count2 THEN
        RAISE NOTICE 'TEST 12 PASSED: Payload is idempotent (spend: %, count: %)', v_spend1, v_count1;
    ELSE
        RAISE WARNING 'TEST 12 FAILED: Payload not idempotent. Call 1: spend=% count=%, Call 2: spend=% count=%',
            v_spend1, v_count1, v_spend2, v_count2;
    END IF;
END $$;
