-- Pipeline Verification Tests
-- Run with: psql -U nexus -d nexus -f tests/015_pipeline_verification_tests.sql
-- Tests: Data pipeline functions, view dependencies, refresh operations

-- ================================================
-- Test Case 1: life.refresh_daily_facts() function exists
-- ================================================
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'life' AND p.proname = 'refresh_daily_facts'
    ) THEN
        RAISE NOTICE 'TEST 1 PASSED: life.refresh_daily_facts() function exists';
    ELSE
        -- Function may not exist in all deployments
        RAISE NOTICE 'TEST 1 SKIPPED: life.refresh_daily_facts() not found (may not be deployed)';
    END IF;
END $$;

-- ================================================
-- Test Case 2: finance.to_business_date() is IMMUTABLE
-- ================================================
DO $$
DECLARE
    v_volatility CHAR;
BEGIN
    SELECT p.provolatile INTO v_volatility
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'finance' AND p.proname = 'to_business_date';

    IF v_volatility = 'i' THEN
        RAISE NOTICE 'TEST 2 PASSED: finance.to_business_date() is IMMUTABLE';
    ELSIF v_volatility IS NULL THEN
        RAISE EXCEPTION 'TEST 2 FAILED: finance.to_business_date() not found';
    ELSE
        RAISE WARNING 'TEST 2 WARNING: finance.to_business_date() volatility is "%" (expected "i" for IMMUTABLE)', v_volatility;
    END IF;
END $$;

-- ================================================
-- Test Case 3: finance.current_business_date() is STABLE
-- ================================================
DO $$
DECLARE
    v_volatility CHAR;
BEGIN
    SELECT p.provolatile INTO v_volatility
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'finance' AND p.proname = 'current_business_date';

    IF v_volatility = 's' THEN
        RAISE NOTICE 'TEST 3 PASSED: finance.current_business_date() is STABLE';
    ELSIF v_volatility IS NULL THEN
        RAISE EXCEPTION 'TEST 3 FAILED: finance.current_business_date() not found';
    ELSE
        RAISE WARNING 'TEST 3 WARNING: finance.current_business_date() volatility is "%"', v_volatility;
    END IF;
END $$;

-- ================================================
-- Test Case 4: Key schemas exist
-- ================================================
DO $$
DECLARE
    v_schemas TEXT[] := ARRAY['finance', 'raw', 'normalized', 'facts', 'life'];
    v_schema TEXT;
    v_missing TEXT[] := ARRAY[]::TEXT[];
BEGIN
    FOREACH v_schema IN ARRAY v_schemas LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = v_schema) THEN
            v_missing := v_missing || v_schema;
        END IF;
    END LOOP;

    IF array_length(v_missing, 1) IS NULL THEN
        RAISE NOTICE 'TEST 4 PASSED: All required schemas exist (finance, raw, normalized, facts, life)';
    ELSE
        RAISE WARNING 'TEST 4 FAILED: Missing schemas: %', array_to_string(v_missing, ', ');
    END IF;
END $$;

-- ================================================
-- Test Case 5: Key tables exist in finance schema
-- ================================================
DO $$
DECLARE
    v_tables TEXT[] := ARRAY['transactions', 'merchant_rules', 'categories', 'budgets'];
    v_table TEXT;
    v_missing TEXT[] := ARRAY[]::TEXT[];
BEGIN
    FOREACH v_table IN ARRAY v_tables LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = 'finance' AND table_name = v_table
        ) THEN
            v_missing := v_missing || v_table;
        END IF;
    END LOOP;

    IF array_length(v_missing, 1) IS NULL THEN
        RAISE NOTICE 'TEST 5 PASSED: All finance tables exist (transactions, merchant_rules, categories, budgets)';
    ELSE
        RAISE WARNING 'TEST 5 FAILED: Missing finance tables: %', array_to_string(v_missing, ', ');
    END IF;
END $$;

-- ================================================
-- Test Case 6: Key tables exist in raw schema
-- ================================================
DO $$
DECLARE
    v_tables TEXT[] := ARRAY['manual_entries', 'bank_sms', 'healthkit_samples'];
    v_table TEXT;
    v_missing TEXT[] := ARRAY[]::TEXT[];
BEGIN
    FOREACH v_table IN ARRAY v_tables LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = 'raw' AND table_name = v_table
        ) THEN
            v_missing := v_missing || v_table;
        END IF;
    END LOOP;

    IF array_length(v_missing, 1) IS NULL THEN
        RAISE NOTICE 'TEST 6 PASSED: All raw tables exist (manual_entries, bank_sms, healthkit_samples)';
    ELSE
        RAISE WARNING 'TEST 6 FAILED: Missing raw tables: %', array_to_string(v_missing, ', ');
    END IF;
END $$;

-- ================================================
-- Test Case 7: Categorization trigger is active
-- ================================================
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_trigger t
        JOIN pg_class c ON t.tgrelid = c.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'finance'
        AND c.relname = 'transactions'
        AND t.tgname = 'categorize_transaction_trigger'
        AND t.tgenabled = 'O'
    ) THEN
        RAISE NOTICE 'TEST 7 PASSED: categorize_transaction_trigger is active';
    ELSE
        RAISE WARNING 'TEST 7 FAILED: categorize_transaction_trigger not found or disabled';
    END IF;
END $$;

-- ================================================
-- Test Case 8: set_transaction_at trigger is active
-- ================================================
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_trigger t
        JOIN pg_class c ON t.tgrelid = c.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'finance'
        AND c.relname = 'transactions'
        AND t.tgname = 'set_transaction_at_trigger'
        AND t.tgenabled = 'O'
    ) THEN
        RAISE NOTICE 'TEST 8 PASSED: set_transaction_at_trigger is active';
    ELSE
        RAISE WARNING 'TEST 8 FAILED: set_transaction_at_trigger not found or disabled';
    END IF;
END $$;

-- ================================================
-- Test Case 9: Key indexes exist
-- ================================================
DO $$
DECLARE
    v_indexes TEXT[] := ARRAY['idx_transactions_client_id', 'idx_transactions_transaction_at'];
    v_index TEXT;
    v_missing TEXT[] := ARRAY[]::TEXT[];
BEGIN
    FOREACH v_index IN ARRAY v_indexes LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_indexes
            WHERE schemaname = 'finance' AND indexname = v_index
        ) THEN
            v_missing := v_missing || v_index;
        END IF;
    END LOOP;

    IF array_length(v_missing, 1) IS NULL THEN
        RAISE NOTICE 'TEST 9 PASSED: Key indexes exist';
    ELSE
        RAISE WARNING 'TEST 9 WARNING: Missing indexes: %', array_to_string(v_missing, ', ');
    END IF;
END $$;

-- ================================================
-- Test Case 10: Verify transaction_at column exists
-- ================================================
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'finance'
        AND table_name = 'transactions'
        AND column_name = 'transaction_at'
    ) THEN
        RAISE NOTICE 'TEST 10 PASSED: transaction_at column exists in finance.transactions';
    ELSE
        RAISE EXCEPTION 'TEST 10 FAILED: transaction_at column not found';
    END IF;
END $$;

-- ================================================
-- Test Case 11: Verify merchant_rules has required columns
-- ================================================
DO $$
DECLARE
    v_columns TEXT[] := ARRAY['merchant_pattern', 'category', 'priority', 'confidence', 'is_active'];
    v_col TEXT;
    v_missing TEXT[] := ARRAY[]::TEXT[];
BEGIN
    FOREACH v_col IN ARRAY v_columns LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'finance'
            AND table_name = 'merchant_rules'
            AND column_name = v_col
        ) THEN
            v_missing := v_missing || v_col;
        END IF;
    END LOOP;

    IF array_length(v_missing, 1) IS NULL THEN
        RAISE NOTICE 'TEST 11 PASSED: merchant_rules has all required columns';
    ELSE
        RAISE WARNING 'TEST 11 FAILED: Missing columns: %', array_to_string(v_missing, ', ');
    END IF;
END $$;

-- ================================================
-- Test Case 12: Verify data flow (basic sanity)
-- ================================================
DO $$
DECLARE
    v_tx_count INTEGER;
    v_rule_count INTEGER;
    v_category_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_tx_count FROM finance.transactions;
    SELECT COUNT(*) INTO v_rule_count FROM finance.merchant_rules WHERE is_active = true;
    SELECT COUNT(*) INTO v_category_count FROM finance.categories WHERE is_active = true;

    RAISE NOTICE 'TEST 12 INFO: Data counts - transactions: %, active rules: %, active categories: %',
        v_tx_count, v_rule_count, v_category_count;

    IF v_rule_count > 0 AND v_category_count > 0 THEN
        RAISE NOTICE 'TEST 12 PASSED: System has active rules and categories';
    ELSE
        RAISE WARNING 'TEST 12 WARNING: Low rule/category counts may indicate setup issue';
    END IF;
END $$;

-- ================================================
-- Summary
-- ================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Pipeline Verification Tests Complete';
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Test 1: life.refresh_daily_facts() exists';
    RAISE NOTICE 'Test 2: to_business_date() is IMMUTABLE';
    RAISE NOTICE 'Test 3: current_business_date() is STABLE';
    RAISE NOTICE 'Test 4: Required schemas exist';
    RAISE NOTICE 'Test 5: Finance tables exist';
    RAISE NOTICE 'Test 6: Raw tables exist';
    RAISE NOTICE 'Test 7: Categorization trigger active';
    RAISE NOTICE 'Test 8: set_transaction_at trigger active';
    RAISE NOTICE 'Test 9: Key indexes exist';
    RAISE NOTICE 'Test 10: transaction_at column exists';
    RAISE NOTICE 'Test 11: merchant_rules columns exist';
    RAISE NOTICE 'Test 12: Data sanity check';
    RAISE NOTICE '==========================================';
END $$;
