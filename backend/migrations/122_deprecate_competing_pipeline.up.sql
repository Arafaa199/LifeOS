-- Migration 122: Deprecate competing facts.refresh_daily_* pipeline
--
-- Problem: life.refresh_all() calls BOTH life.refresh_daily_facts() AND
-- facts.refresh_daily_health()/facts.refresh_daily_finance(). The facts.*
-- functions write to facts.daily_health / facts.daily_finance, but the
-- dashboard reads ONLY from life.daily_facts. The facts.* calls are wasted
-- work that can mask failures and confuse debugging.
--
-- Fix: Remove facts.* calls from life.refresh_all(). Leave the functions
-- in place (do NOT drop) so they can be called manually if needed during
-- the transition period. Add deprecation comments.
--
-- The facts.* functions and tables will be removed in a future migration
-- after stability is proven.

-- =============================================================================
-- 1. Rewrite life.refresh_all(p_days, p_caller) — JSONB overload
-- =============================================================================

CREATE OR REPLACE FUNCTION life.refresh_all(p_days integer DEFAULT 1, p_caller text DEFAULT 'manual'::text)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    v_start DATE;
    v_end DATE;
    v_day DATE;
    v_refreshed INTEGER := 0;
    v_errors INTEGER := 0;
    v_result JSONB;
BEGIN
    PERFORM life.reset_feed_events_today();

    v_end := life.dubai_today();
    v_start := v_end - (p_days - 1);

    FOR v_day IN SELECT generate_series(v_start, v_end, '1 day'::interval)::date
    LOOP
        BEGIN
            PERFORM life.refresh_daily_facts(v_day);
            v_refreshed := v_refreshed + 1;
        EXCEPTION WHEN OTHERS THEN
            v_errors := v_errors + 1;
            INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
            VALUES ('life.refresh_all', 'life.daily_facts',
                    SQLERRM, format('day=%s caller=%s', v_day, p_caller));
            RAISE WARNING 'refresh_all: failed for % — %', v_day, SQLERRM;
        END;

        -- DEPRECATED (migration 122): facts.refresh_daily_health() and
        -- facts.refresh_daily_finance() removed. life.refresh_daily_facts()
        -- now reads directly from normalized layer (migration 120).
    END LOOP;

    BEGIN
        PERFORM finance.refresh_financial_truth();
    EXCEPTION WHEN OTHERS THEN
        v_errors := v_errors + 1;
        INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
        VALUES ('life.refresh_all', 'finance.mv_*', SQLERRM, format('caller=%s', p_caller));
        RAISE WARNING 'refresh_all: finance.refresh_financial_truth() failed — %', SQLERRM;
    END;

    v_result := jsonb_build_object(
        'refreshed_days', v_refreshed,
        'errors', v_errors,
        'range', format('%s..%s', v_start, v_end),
        'caller', p_caller,
        'completed_at', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
    );

    RAISE NOTICE 'refresh_all complete: %', v_result;
    RETURN v_result;
END;
$function$;

-- =============================================================================
-- 2. Rewrite life.refresh_all(days_back, triggered_by) — TABLE overload
-- =============================================================================

CREATE OR REPLACE FUNCTION life.refresh_all(days_back integer DEFAULT 2, triggered_by character varying DEFAULT 'manual'::character varying)
RETURNS TABLE(day date, status text, rows_affected integer, duration_ms integer)
LANGUAGE plpgsql
AS $function$
DECLARE
    d DATE;
    result RECORD;
    today_dubai DATE := life.dubai_today();
BEGIN
    PERFORM life.reset_feed_events_today();

    FOR d IN SELECT generate_series(
        today_dubai - days_back,
        today_dubai,
        '1 day'::interval
    )::date
    LOOP
        SELECT * INTO result FROM life.refresh_daily_facts(d, triggered_by);
        RETURN QUERY SELECT d, result.status, result.rows_affected, result.duration_ms;

        -- DEPRECATED (migration 122): facts.refresh_daily_health() and
        -- facts.refresh_daily_finance() removed from this loop.
    END LOOP;

    PERFORM life.refresh_baselines(triggered_by);

    RETURN;
END;
$function$;

-- =============================================================================
-- 3. Mark facts.* refresh functions as deprecated (comments only)
-- =============================================================================

COMMENT ON FUNCTION facts.refresh_daily_health(date) IS
'DEPRECATED (migration 122): No longer called by life.refresh_all(). '
'life.refresh_daily_facts() now reads directly from normalized layer. '
'Will be removed in a future migration after stability is proven.';

COMMENT ON FUNCTION facts.refresh_daily_finance(date) IS
'DEPRECATED (migration 122): No longer called by life.refresh_all(). '
'life.refresh_daily_facts() now reads normalized.v_daily_finance. '
'Will be removed in a future migration after stability is proven.';

COMMENT ON FUNCTION facts.refresh_daily_nutrition(date) IS
'DEPRECATED (migration 122): Was never called by life.refresh_all(). '
'life.refresh_daily_facts() now reads normalized.food_log/water_log directly. '
'Will be removed in a future migration after stability is proven.';

COMMENT ON FUNCTION facts.refresh_daily_summary(date) IS
'DEPRECATED (migration 122): Depends on facts.daily_health which is no longer refreshed. '
'Will be removed in a future migration after stability is proven.';

-- Also upgrade RAISE NOTICE to RAISE WARNING in the JSONB overload for consistency
-- (the TABLE overload already propagates errors via result rows)

COMMENT ON FUNCTION life.refresh_all(integer, text) IS
'Single-pipeline refresh (JSONB overload). Calls life.refresh_daily_facts() per day '
'+ finance.refresh_financial_truth(). Migration 122: removed facts.* calls.';

COMMENT ON FUNCTION life.refresh_all(integer, varchar) IS
'Single-pipeline refresh (TABLE overload). Calls life.refresh_daily_facts() per day '
'+ life.refresh_baselines(). Migration 122: removed facts.* calls.';
