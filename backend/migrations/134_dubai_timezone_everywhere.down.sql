-- Migration 134 DOWN: Revert life.dubai_today() back to CURRENT_DATE
--
-- This reversal uses the same dynamic approach as the up migration,
-- replacing life.dubai_today() back to CURRENT_DATE across all objects.

BEGIN;

-- ============================================================================
-- PHASE 1: Revert views
-- ============================================================================

DO $$
DECLARE
    v_schema text;
    v_name text;
    v_def text;
    v_new_def text;
    v_count int := 0;
BEGIN
    FOR v_schema, v_name, v_def IN
        SELECT schemaname, viewname, definition
        FROM pg_views
        WHERE schemaname IN (
            'finance', 'life', 'insights', 'ops', 'core',
            'dashboard', 'health', 'nutrition', 'normalized'
        )
        AND definition ~* 'life\.dubai_today\(\)'
        ORDER BY schemaname, viewname
    LOOP
        v_new_def := regexp_replace(v_def, 'life\.dubai_today\(\)', 'CURRENT_DATE', 'gi');

        IF v_new_def = v_def THEN
            CONTINUE;
        END IF;

        BEGIN
            EXECUTE format('CREATE OR REPLACE VIEW %I.%I AS %s', v_schema, v_name, v_new_def);
            v_count := v_count + 1;
            RAISE NOTICE 'Reverted view: %.%', v_schema, v_name;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Failed to revert view %.%: %', v_schema, v_name, SQLERRM;
        END;
    END LOOP;

    RAISE NOTICE 'Phase 1 complete: % views reverted', v_count;
END;
$$;

-- ============================================================================
-- PHASE 2: Revert functions
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
        AND pg_get_functiondef(p.oid) ~* 'life\.dubai_today\(\)'
        AND NOT (n.nspname = 'life' AND p.proname = 'dubai_today')
        AND NOT (n.nspname = 'finance' AND p.proname = 'current_business_date')
        AND NOT (n.nspname = 'finance' AND p.proname = 'to_business_date')
        ORDER BY n.nspname, p.proname
    LOOP
        v_def := pg_get_functiondef(v_oid);
        v_new_def := regexp_replace(v_def, 'life\.dubai_today\(\)', 'CURRENT_DATE', 'gi');

        IF v_new_def = v_def THEN
            CONTINUE;
        END IF;

        BEGIN
            EXECUTE v_new_def;
            v_count := v_count + 1;
            RAISE NOTICE 'Reverted function: %.%', v_schema, v_name;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Failed to revert function %.% (oid %): %', v_schema, v_name, v_oid, SQLERRM;
        END;
    END LOOP;

    RAISE NOTICE 'Phase 2 complete: % functions reverted', v_count;
END;
$$;

-- ============================================================================
-- PHASE 3: Revert materialized views
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
        AND definition ~* 'life\.dubai_today\(\)'
        ORDER BY schemaname, matviewname
    LOOP
        v_new_def := regexp_replace(v_def, 'life\.dubai_today\(\)', 'CURRENT_DATE', 'gi');

        IF v_new_def = v_def THEN
            CONTINUE;
        END IF;

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

            FOR i IN 1..coalesce(array_length(v_indexes, 1), 0) LOOP
                EXECUTE v_indexes[i];
            END LOOP;

            EXECUTE format('REFRESH MATERIALIZED VIEW %I.%I', v_schema, v_name);

            v_count := v_count + 1;
            RAISE NOTICE 'Reverted materialized view: %.%', v_schema, v_name;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Failed to revert materialized view %.%: %', v_schema, v_name, SQLERRM;
        END;
    END LOOP;

    RAISE NOTICE 'Phase 3 complete: % materialized views reverted', v_count;
END;
$$;

COMMIT;
