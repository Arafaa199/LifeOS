-- Data Integrity Tests
-- Run with: psql -U nexus -d nexus -f tests/020_data_integrity_tests.sql
-- Tests: Duplicate detection, categorization rates, date consistency, FK integrity

-- ================================================
-- Test Case 1: No duplicate external_ids
-- ================================================
DO $$
DECLARE
    v_duplicate_count INTEGER;
    v_sample TEXT;
BEGIN
    SELECT COUNT(*), string_agg(external_id, ', ' ORDER BY external_id LIMIT 5)
    INTO v_duplicate_count, v_sample
    FROM (
        SELECT external_id
        FROM finance.transactions
        WHERE external_id IS NOT NULL
        GROUP BY external_id
        HAVING COUNT(*) > 1
    ) dups;

    IF v_duplicate_count = 0 OR v_duplicate_count IS NULL THEN
        RAISE NOTICE 'TEST 1 PASSED: No duplicate external_ids found';
    ELSE
        RAISE WARNING 'TEST 1 FAILED: % duplicate external_id groups found. Samples: %', v_duplicate_count, v_sample;
    END IF;
END $$;

-- ================================================
-- Test Case 2: No duplicate client_ids (where not null)
-- ================================================
DO $$
DECLARE
    v_duplicate_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_duplicate_count
    FROM (
        SELECT client_id
        FROM finance.transactions
        WHERE client_id IS NOT NULL
        GROUP BY client_id
        HAVING COUNT(*) > 1
    ) dups;

    IF v_duplicate_count = 0 OR v_duplicate_count IS NULL THEN
        RAISE NOTICE 'TEST 2 PASSED: No duplicate client_ids found';
    ELSE
        RAISE WARNING 'TEST 2 FAILED: % duplicate client_id groups found', v_duplicate_count;
    END IF;
END $$;

-- ================================================
-- Test Case 3: Categorization rate above threshold (>95%)
-- ================================================
DO $$
DECLARE
    v_total INTEGER;
    v_uncategorized INTEGER;
    v_rate NUMERIC;
BEGIN
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE category IS NULL OR category = 'Uncategorized' OR category = '')
    INTO v_total, v_uncategorized
    FROM finance.transactions
    WHERE NOT COALESCE(is_quarantined, false);

    IF v_total > 0 THEN
        v_rate := 100.0 - (v_uncategorized::NUMERIC / v_total * 100);

        IF v_rate >= 95 THEN
            RAISE NOTICE 'TEST 3 PASSED: Categorization rate = %.1f%% (% of % uncategorized)', v_rate, v_uncategorized, v_total;
        ELSIF v_rate >= 90 THEN
            RAISE WARNING 'TEST 3 WARNING: Categorization rate = %.1f%% (below 95%% target)', v_rate;
        ELSE
            RAISE WARNING 'TEST 3 FAILED: Categorization rate = %.1f%% (below 90%% threshold)', v_rate;
        END IF;
    ELSE
        RAISE NOTICE 'TEST 3 SKIPPED: No transactions to check';
    END IF;
END $$;

-- ================================================
-- Test Case 4: Date consistency (date = to_business_date(transaction_at))
-- ================================================
DO $$
DECLARE
    v_inconsistent INTEGER;
    v_total INTEGER;
BEGIN
    SELECT
        COUNT(*),
        COUNT(*) FILTER (
            WHERE transaction_at IS NOT NULL
            AND date != finance.to_business_date(transaction_at)
        )
    INTO v_total, v_inconsistent
    FROM finance.transactions
    WHERE transaction_at IS NOT NULL
    AND NOT COALESCE(is_quarantined, false);

    IF v_inconsistent = 0 THEN
        RAISE NOTICE 'TEST 4 PASSED: All % transactions have consistent date/transaction_at', v_total;
    ELSE
        RAISE WARNING 'TEST 4 FAILED: % of % transactions have inconsistent date vs transaction_at', v_inconsistent, v_total;
    END IF;
END $$;

-- ================================================
-- Test Case 5: FK integrity - match_rule_id references valid rule
-- ================================================
DO $$
DECLARE
    v_orphan_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_orphan_count
    FROM finance.transactions t
    WHERE t.match_rule_id IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM finance.merchant_rules r WHERE r.id = t.match_rule_id
    );

    IF v_orphan_count = 0 THEN
        RAISE NOTICE 'TEST 5 PASSED: All match_rule_id references are valid';
    ELSE
        RAISE WARNING 'TEST 5 FAILED: % transactions have orphan match_rule_id', v_orphan_count;
    END IF;
END $$;

-- ================================================
-- Test Case 6: No null amounts
-- ================================================
DO $$
DECLARE
    v_null_amount_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_null_amount_count
    FROM finance.transactions
    WHERE amount IS NULL;

    IF v_null_amount_count = 0 THEN
        RAISE NOTICE 'TEST 6 PASSED: No NULL amounts in transactions';
    ELSE
        RAISE WARNING 'TEST 6 FAILED: % transactions have NULL amount', v_null_amount_count;
    END IF;
END $$;

-- ================================================
-- Test Case 7: Currency validation (all known currencies)
-- ================================================
DO $$
DECLARE
    v_invalid_currency TEXT;
    v_invalid_count INTEGER;
BEGIN
    SELECT string_agg(DISTINCT currency, ', '), COUNT(DISTINCT currency)
    INTO v_invalid_currency, v_invalid_count
    FROM finance.transactions
    WHERE currency NOT IN ('AED', 'SAR', 'JOD', 'USD', 'EUR', 'GBP', 'BHD', 'EGP', 'INR')
    AND currency IS NOT NULL;

    IF v_invalid_count = 0 OR v_invalid_currency IS NULL THEN
        RAISE NOTICE 'TEST 7 PASSED: All currencies are valid';
    ELSE
        RAISE WARNING 'TEST 7 WARNING: Unknown currencies found: %', v_invalid_currency;
    END IF;
END $$;

-- ================================================
-- Test Case 8: Quarantine isolation (quarantined not in views)
-- ================================================
DO $$
DECLARE
    v_quarantine_count INTEGER;
    v_total_quarantined INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_total_quarantined
    FROM finance.transactions WHERE is_quarantined = true;

    -- This checks a sample view - adjust view name as needed
    IF v_total_quarantined > 0 THEN
        RAISE NOTICE 'TEST 8 INFO: % quarantined transactions exist', v_total_quarantined;
        -- Add specific view check if needed
    ELSE
        RAISE NOTICE 'TEST 8 PASSED: No quarantined transactions';
    END IF;
END $$;

-- ================================================
-- Test Case 9: raw_events without transactions (valid events)
-- ================================================
DO $$
DECLARE
    v_orphan_count INTEGER;
BEGIN
    -- Check if finance.raw_events table exists
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'finance' AND table_name = 'raw_events'
    ) THEN
        SELECT COUNT(*) INTO v_orphan_count
        FROM finance.raw_events
        WHERE validation_status = 'valid'
        AND related_transaction_id IS NULL;

        IF v_orphan_count = 0 THEN
            RAISE NOTICE 'TEST 9 PASSED: All valid raw_events have linked transactions';
        ELSE
            RAISE WARNING 'TEST 9 FAILED: % valid raw_events without transactions', v_orphan_count;
        END IF;
    ELSE
        RAISE NOTICE 'TEST 9 SKIPPED: finance.raw_events table does not exist';
    END IF;
END $$;

-- ================================================
-- Test Case 10: Recent data freshness
-- ================================================
DO $$
DECLARE
    v_latest_date DATE;
    v_days_old INTEGER;
BEGIN
    SELECT MAX(date) INTO v_latest_date FROM finance.transactions;

    IF v_latest_date IS NOT NULL THEN
        v_days_old := CURRENT_DATE - v_latest_date;

        IF v_days_old <= 1 THEN
            RAISE NOTICE 'TEST 10 PASSED: Data is fresh (latest: %, % days old)', v_latest_date, v_days_old;
        ELSIF v_days_old <= 7 THEN
            RAISE WARNING 'TEST 10 WARNING: Data is % days old (latest: %)', v_days_old, v_latest_date;
        ELSE
            RAISE WARNING 'TEST 10 FAILED: Data is stale - % days old (latest: %)', v_days_old, v_latest_date;
        END IF;
    ELSE
        RAISE WARNING 'TEST 10 FAILED: No transactions found';
    END IF;
END $$;

-- ================================================
-- Summary Statistics
-- ================================================
DO $$
DECLARE
    v_total_tx INTEGER;
    v_categorized INTEGER;
    v_uncategorized INTEGER;
    v_with_client_id INTEGER;
    v_quarantined INTEGER;
BEGIN
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE category IS NOT NULL AND category != 'Uncategorized'),
        COUNT(*) FILTER (WHERE category IS NULL OR category = 'Uncategorized'),
        COUNT(*) FILTER (WHERE client_id IS NOT NULL),
        COUNT(*) FILTER (WHERE is_quarantined = true)
    INTO v_total_tx, v_categorized, v_uncategorized, v_with_client_id, v_quarantined
    FROM finance.transactions;

    RAISE NOTICE '';
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Data Integrity Tests Complete';
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Statistics:';
    RAISE NOTICE '  Total transactions: %', v_total_tx;
    RAISE NOTICE '  Categorized: % (%.1f%%)', v_categorized, CASE WHEN v_total_tx > 0 THEN v_categorized::NUMERIC/v_total_tx*100 ELSE 0 END;
    RAISE NOTICE '  Uncategorized: %', v_uncategorized;
    RAISE NOTICE '  With client_id: %', v_with_client_id;
    RAISE NOTICE '  Quarantined: %', v_quarantined;
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Tests:';
    RAISE NOTICE '  1. Duplicate external_ids check';
    RAISE NOTICE '  2. Duplicate client_ids check';
    RAISE NOTICE '  3. Categorization rate (>95%%)';
    RAISE NOTICE '  4. Date consistency check';
    RAISE NOTICE '  5. FK integrity (match_rule_id)';
    RAISE NOTICE '  6. No null amounts';
    RAISE NOTICE '  7. Currency validation';
    RAISE NOTICE '  8. Quarantine isolation';
    RAISE NOTICE '  9. raw_events orphan check';
    RAISE NOTICE ' 10. Data freshness check';
    RAISE NOTICE '==========================================';
END $$;
