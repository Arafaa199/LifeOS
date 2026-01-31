-- Down migration 098: Revert refresh_all to not call facts.refresh_daily_health
-- Does NOT delete facts.daily_health rows (data is still valid, just won't auto-refresh)

BEGIN;

-- Restore original life.refresh_all (INTEGER, TEXT overload)
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
    END LOOP;

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

-- Restore original life.refresh_all (INTEGER, VARCHAR overload)
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
    END LOOP;

    PERFORM life.refresh_baselines(triggered_by);

    RETURN;
END;
$function$;

COMMIT;
