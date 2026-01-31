-- Migration 099: Wire life.reset_feed_events_today() into life.refresh_all()
-- TASK-PLAN.7: Reset events_today counters during nightly refresh
-- so they reflect daily counts instead of accumulating indefinitely.

BEGIN;

-- Overload 1: (p_days, p_caller) → jsonb
CREATE OR REPLACE FUNCTION life.refresh_all(
    p_days INTEGER DEFAULT 1,
    p_caller TEXT DEFAULT 'manual'
) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
    v_start DATE;
    v_end DATE;
    v_day DATE;
    v_refreshed INTEGER := 0;
    v_errors INTEGER := 0;
    v_result JSONB;
BEGIN
    -- Reset daily feed counters at start of refresh
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
$$;

-- Overload 2: (days_back, triggered_by) → TABLE
CREATE OR REPLACE FUNCTION life.refresh_all(
    days_back INTEGER DEFAULT 2,
    triggered_by VARCHAR DEFAULT 'manual'
) RETURNS TABLE(day DATE, status TEXT, rows_affected INTEGER, duration_ms INTEGER)
LANGUAGE plpgsql AS $$
DECLARE
    d DATE;
    result RECORD;
    today_dubai DATE := life.dubai_today();
BEGIN
    -- Reset daily feed counters at start of refresh
    PERFORM life.reset_feed_events_today();

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
$$;

COMMIT;
