-- Migration 098: Wire HealthKit steps + weight into facts.daily_health via refresh_all
-- TASK-PLAN.5: Ensures facts.daily_health is refreshed alongside life.daily_facts

BEGIN;

-- 1. Replace life.refresh_all (INTEGER, TEXT overload) to also call facts.refresh_daily_health
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
            RAISE NOTICE 'refresh_all: failed for % — %', v_day, SQLERRM;
        END;

        -- Also refresh facts.daily_health for this day
        BEGIN
            PERFORM facts.refresh_daily_health(v_day);
        EXCEPTION WHEN OTHERS THEN
            v_errors := v_errors + 1;
            INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
            VALUES ('life.refresh_all', 'facts.daily_health',
                    SQLERRM, format('day=%s caller=%s', v_day, p_caller));
            RAISE NOTICE 'refresh_all: facts.refresh_daily_health failed for % — %', v_day, SQLERRM;
        END;
    END LOOP;

    -- Refresh financial materialized views
    BEGIN
        PERFORM finance.refresh_financial_truth();
    EXCEPTION WHEN OTHERS THEN
        v_errors := v_errors + 1;
        INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
        VALUES ('life.refresh_all', 'finance.mv_*', SQLERRM, format('caller=%s', p_caller));
        RAISE NOTICE 'refresh_all: finance.refresh_financial_truth() failed — %', SQLERRM;
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

-- 2. Replace life.refresh_all (INTEGER, VARCHAR overload) to also call facts.refresh_daily_health
CREATE OR REPLACE FUNCTION life.refresh_all(days_back integer DEFAULT 2, triggered_by character varying DEFAULT 'manual'::character varying)
 RETURNS TABLE(day date, status text, rows_affected integer, duration_ms integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    d DATE;
    result RECORD;
    today_dubai DATE := life.dubai_today();
BEGIN
    FOR d IN SELECT generate_series(
        today_dubai - days_back,
        today_dubai,
        '1 day'::interval
    )::date
    LOOP
        SELECT * INTO result FROM life.refresh_daily_facts(d, triggered_by);
        RETURN QUERY SELECT d, result.status, result.rows_affected, result.duration_ms;

        -- Also refresh facts.daily_health for this day
        BEGIN
            PERFORM facts.refresh_daily_health(d);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'refresh_all: facts.refresh_daily_health failed for % — %', d, SQLERRM;
        END;
    END LOOP;

    -- Refresh baselines after facts
    PERFORM life.refresh_baselines(triggered_by);

    RETURN;
END;
$function$;

-- 3. Backfill facts.daily_health for all dates that have ANY health data
DO $$
DECLARE
    d DATE;
BEGIN
    FOR d IN
        SELECT DISTINCT dt FROM (
            SELECT date AS dt FROM health.whoop_recovery
            UNION
            SELECT date AS dt FROM health.whoop_sleep
            UNION
            SELECT date AS dt FROM health.whoop_strain
            UNION
            SELECT DISTINCT (start_date AT TIME ZONE 'Asia/Dubai')::date AS dt
            FROM raw.healthkit_samples
        ) all_dates
        ORDER BY dt
    LOOP
        PERFORM facts.refresh_daily_health(d);
    END LOOP;
END $$;

COMMIT;
