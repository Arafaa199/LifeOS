-- Migration 134: Replace CURRENT_DATE with life.dubai_today() everywhere
--
-- Problem: All views and functions use CURRENT_DATE which resolves to UTC.
-- Since the system operates in Dubai time (UTC+4), date boundaries are wrong
-- for ~4 hours every day (20:00-00:00 Dubai = next day in UTC).
--
-- Solution: Dynamically iterate all views and functions in application schemas,
-- replace CURRENT_DATE with life.dubai_today(), and recreate them.
--
-- life.dubai_today() is defined as:
--   (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Dubai')::date
--
-- finance.current_business_date() is an alias for the same.
--
-- This migration is idempotent: running it again on already-fixed objects is a no-op
-- (regexp_replace won't match if CURRENT_DATE is already gone).

BEGIN;

-- ============================================================================
-- PHASE 1: Fix all views
-- ============================================================================
-- CREATE OR REPLACE VIEW preserves grants and dependencies.
-- We only change expression logic (CURRENT_DATE -> life.dubai_today()),
-- never column types or names, so dependent views remain valid.
-- ============================================================================

DO $$
DECLARE
    v_schema text;
    v_name text;
    v_def text;
    v_new_def text;
    v_count int := 0;
BEGIN
    -- Process views in dependency order: leaf views first won't matter here
    -- because CREATE OR REPLACE VIEW doesn't drop anything, and we're only
    -- changing expression internals (not output columns).
    FOR v_schema, v_name, v_def IN
        SELECT schemaname, viewname, definition
        FROM pg_views
        WHERE schemaname IN (
            'finance', 'life', 'insights', 'ops', 'core',
            'dashboard', 'health', 'nutrition', 'normalized'
        )
        AND definition ~* 'current_date'
        ORDER BY schemaname, viewname
    LOOP
        v_new_def := regexp_replace(v_def, 'CURRENT_DATE', 'life.dubai_today()', 'gi');

        -- Skip if nothing changed (already uses dubai_today)
        IF v_new_def = v_def THEN
            CONTINUE;
        END IF;

        BEGIN
            EXECUTE format('CREATE OR REPLACE VIEW %I.%I AS %s', v_schema, v_name, v_new_def);
            v_count := v_count + 1;
            RAISE NOTICE 'Updated view: %.%', v_schema, v_name;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Failed to update view %.%: %', v_schema, v_name, SQLERRM;
        END;
    END LOOP;

    RAISE NOTICE 'Phase 1 complete: % views updated', v_count;
END;
$$;

-- ============================================================================
-- PHASE 2: Fix all functions
-- ============================================================================
-- pg_get_functiondef() returns the full CREATE OR REPLACE FUNCTION statement
-- including parameter defaults, so replacing CURRENT_DATE catches both:
--   - DEFAULT CURRENT_DATE in parameter lists
--   - CURRENT_DATE in function bodies
--
-- We skip the timezone functions themselves to avoid circular references.
-- ============================================================================

DO $$
DECLARE
    v_schema text;
    v_name text;
    v_oid oid;
    v_def text;
    v_new_def text;
    v_count int := 0;
BEGIN
    FOR v_schema, v_name, v_oid IN
        SELECT n.nspname, p.proname, p.oid
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname IN (
            'finance', 'life', 'insights', 'ops', 'core',
            'dashboard', 'health', 'nutrition', 'normalized'
        )
        AND p.prokind IN ('f', 'p')  -- functions and procedures only (skip aggregates/window)
        AND pg_get_functiondef(p.oid) ~* 'current_date'
        -- Skip the timezone functions themselves
        AND NOT (n.nspname = 'life' AND p.proname = 'dubai_today')
        AND NOT (n.nspname = 'finance' AND p.proname = 'current_business_date')
        AND NOT (n.nspname = 'finance' AND p.proname = 'to_business_date')
        ORDER BY n.nspname, p.proname
    LOOP
        v_def := pg_get_functiondef(v_oid);
        v_new_def := regexp_replace(v_def, 'CURRENT_DATE', 'life.dubai_today()', 'gi');

        -- Skip if nothing changed
        IF v_new_def = v_def THEN
            CONTINUE;
        END IF;

        BEGIN
            EXECUTE v_new_def;
            v_count := v_count + 1;
            RAISE NOTICE 'Updated function: %.%', v_schema, v_name;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Failed to update function %.% (oid %): %', v_schema, v_name, v_oid, SQLERRM;
        END;
    END LOOP;

    RAISE NOTICE 'Phase 2 complete: % functions updated', v_count;
END;
$$;

-- ============================================================================
-- PHASE 3: Fix materialized views
-- ============================================================================
-- Materialized views cannot use CREATE OR REPLACE. We must DROP and CREATE.
-- This means we lose any indexes on them, so we recreate those too.
-- We also REFRESH after recreation.
-- ============================================================================

DO $$
DECLARE
    v_schema text;
    v_name text;
    v_def text;
    v_new_def text;
    v_idx record;
    v_indexes text[];
    v_count int := 0;
BEGIN
    FOR v_schema, v_name, v_def IN
        SELECT schemaname, matviewname, definition
        FROM pg_matviews
        WHERE schemaname IN (
            'finance', 'life', 'insights', 'ops', 'core',
            'dashboard', 'health', 'nutrition', 'normalized'
        )
        AND definition ~* 'current_date'
        ORDER BY schemaname, matviewname
    LOOP
        v_new_def := regexp_replace(v_def, 'CURRENT_DATE', 'life.dubai_today()', 'gi');

        IF v_new_def = v_def THEN
            CONTINUE;
        END IF;

        -- Save index definitions before dropping
        v_indexes := ARRAY[]::text[];
        FOR v_idx IN
            SELECT indexdef
            FROM pg_indexes
            WHERE schemaname = v_schema
            AND tablename = v_name
        LOOP
            v_indexes := array_append(v_indexes, v_idx.indexdef);
        END LOOP;

        BEGIN
            EXECUTE format('DROP MATERIALIZED VIEW %I.%I', v_schema, v_name);
            EXECUTE format('CREATE MATERIALIZED VIEW %I.%I AS %s', v_schema, v_name, v_new_def);

            -- Recreate indexes
            FOR i IN 1..coalesce(array_length(v_indexes, 1), 0) LOOP
                EXECUTE v_indexes[i];
            END LOOP;

            -- Refresh with data
            EXECUTE format('REFRESH MATERIALIZED VIEW %I.%I', v_schema, v_name);

            v_count := v_count + 1;
            RAISE NOTICE 'Updated materialized view: %.% (% indexes recreated)', v_schema, v_name, coalesce(array_length(v_indexes, 1), 0);
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Failed to update materialized view %.%: %', v_schema, v_name, SQLERRM;
        END;
    END LOOP;

    RAISE NOTICE 'Phase 3 complete: % materialized views updated', v_count;
END;
$$;

-- ============================================================================
-- PHASE 4: Verification
-- ============================================================================

DO $$
DECLARE
    v_remaining_views int;
    v_remaining_funcs int;
    v_remaining_matviews int;
BEGIN
    SELECT count(*) INTO v_remaining_views
    FROM pg_views
    WHERE schemaname IN ('finance', 'life', 'insights', 'ops', 'core', 'dashboard', 'health', 'nutrition', 'normalized')
    AND definition ~* '\mcurrent_date\M'
    AND definition !~* 'dubai_today';

    SELECT count(*) INTO v_remaining_funcs
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname IN ('finance', 'life', 'insights', 'ops', 'core', 'dashboard', 'health', 'nutrition', 'normalized')
    AND p.prokind IN ('f', 'p')
    AND pg_get_functiondef(p.oid) ~* '\mcurrent_date\M'
    AND NOT (n.nspname = 'life' AND p.proname = 'dubai_today')
    AND NOT (n.nspname = 'finance' AND p.proname IN ('current_business_date', 'to_business_date'));

    SELECT count(*) INTO v_remaining_matviews
    FROM pg_matviews
    WHERE schemaname IN ('finance', 'life', 'insights', 'ops', 'core', 'dashboard', 'health', 'nutrition', 'normalized')
    AND definition ~* '\mcurrent_date\M';

    RAISE NOTICE '=== VERIFICATION ===';
    RAISE NOTICE 'Remaining views with CURRENT_DATE: %', v_remaining_views;
    RAISE NOTICE 'Remaining functions with CURRENT_DATE: %', v_remaining_funcs;
    RAISE NOTICE 'Remaining materialized views with CURRENT_DATE: %', v_remaining_matviews;

    IF v_remaining_views + v_remaining_funcs + v_remaining_matviews > 0 THEN
        RAISE WARNING 'Some objects still contain CURRENT_DATE - check warnings above for failures';
    ELSE
        RAISE NOTICE 'All objects successfully migrated to life.dubai_today()';
    END IF;
END;
$$;

COMMIT;
