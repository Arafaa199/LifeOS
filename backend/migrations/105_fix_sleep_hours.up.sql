-- Migration 105: Fix sleep_hours/deep_sleep_hours derivation in life.refresh_daily_facts()
-- Problem: sleep_minutes is populated but sleep_hours/deep_sleep_hours are always NULL,
-- breaking all sleep correlation views in the insights schema.

-- Step 1: Backfill existing rows
UPDATE life.daily_facts
SET sleep_hours = ROUND(sleep_minutes::numeric / 60, 2),
    deep_sleep_hours = ROUND(deep_sleep_minutes::numeric / 60, 2)
WHERE sleep_minutes IS NOT NULL AND sleep_hours IS NULL;

-- Step 2: Replace refresh_daily_facts to include sleep_hours/deep_sleep_hours
CREATE OR REPLACE FUNCTION life.refresh_daily_facts(target_day date DEFAULT NULL::date, triggered_by character varying DEFAULT 'manual'::character varying)
 RETURNS TABLE(status text, rows_affected integer, duration_ms integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    the_day DATE;
    lock_id BIGINT;
    start_time TIMESTAMPTZ;
    end_time TIMESTAMPTZ;
    affected INT;
    log_id INT;
    run_uuid UUID;
BEGIN
    the_day := COALESCE(target_day, life.dubai_today());
    lock_id := ('x' || md5('refresh_daily_facts_' || the_day::text))::bit(32)::int;

    IF NOT pg_try_advisory_lock(lock_id) THEN
        RETURN QUERY SELECT 'skipped'::TEXT, 0, 0;
        RETURN;
    END IF;

    run_uuid := gen_random_uuid();
    start_time := clock_timestamp();

    INSERT INTO ops.refresh_log (run_id, operation, target_day, triggered_by)
    VALUES (run_uuid, 'refresh_daily_facts', the_day, triggered_by)
    RETURNING id INTO log_id;

    BEGIN
        INSERT INTO life.daily_facts (
            day,
            recovery_score, hrv, rhr, spo2,
            sleep_minutes, deep_sleep_minutes, rem_sleep_minutes, sleep_efficiency, sleep_performance,
            sleep_hours, deep_sleep_hours,
            strain, calories_active,
            weight_kg,
            spend_total, spend_groceries, spend_restaurants, spend_transport, income_total, transaction_count,
            meals_logged, water_ml, calories_consumed, protein_g,
            data_completeness, computed_at
        )
        SELECT
            the_day,
            r.recovery_score,
            r.hrv_rmssd,
            r.rhr,
            r.spo2,
            s.time_in_bed_min - COALESCE(s.awake_min, 0),
            s.deep_sleep_min,
            s.rem_sleep_min,
            s.sleep_efficiency,
            s.sleep_performance,
            ROUND((s.time_in_bed_min - COALESCE(s.awake_min, 0))::numeric / 60, 2),
            ROUND(s.deep_sleep_min::numeric / 60, 2),
            st.day_strain,
            st.calories_active,
            (SELECT value FROM health.metrics
             WHERE metric_type = 'weight'
               AND life.to_dubai_date(recorded_at) = the_day
             ORDER BY recorded_at DESC LIMIT 1),
            COALESCE(ABS(SUM(CASE WHEN t.amount < 0 AND NOT t.is_quarantined THEN t.amount ELSE 0 END)), 0),
            COALESCE(ABS(SUM(CASE WHEN t.amount < 0 AND t.category = 'Groceries' AND NOT t.is_quarantined THEN t.amount ELSE 0 END)), 0),
            COALESCE(ABS(SUM(CASE WHEN t.amount < 0 AND t.category IN ('Dining', 'Restaurants', 'Food Delivery') AND NOT t.is_quarantined THEN t.amount ELSE 0 END)), 0),
            COALESCE(ABS(SUM(CASE WHEN t.amount < 0 AND t.category = 'Transport' AND NOT t.is_quarantined THEN t.amount ELSE 0 END)), 0),
            COALESCE(SUM(CASE WHEN t.amount > 0 AND NOT t.is_quarantined THEN t.amount ELSE 0 END), 0),
            COUNT(t.id) FILTER (WHERE NOT t.is_quarantined),
            COALESCE(ds.meals_logged, 0),
            COALESCE(ds.water_ml, 0),
            ds.calories_consumed,
            ds.protein_g,
            (
                CASE WHEN r.recovery_score IS NOT NULL THEN 0.2 ELSE 0 END +
                CASE WHEN s.time_in_bed_min IS NOT NULL THEN 0.2 ELSE 0 END +
                CASE WHEN st.day_strain IS NOT NULL THEN 0.15 ELSE 0 END +
                CASE WHEN EXISTS (SELECT 1 FROM health.metrics WHERE metric_type = 'weight' AND life.to_dubai_date(recorded_at) = the_day) THEN 0.15 ELSE 0 END +
                CASE WHEN COUNT(t.id) FILTER (WHERE NOT t.is_quarantined) > 0 THEN 0.15 ELSE 0 END +
                CASE WHEN ds.calories_consumed IS NOT NULL THEN 0.15 ELSE 0 END
            ),
            NOW()
        FROM
            (SELECT 1) AS dummy
            LEFT JOIN LATERAL (
                SELECT * FROM health.whoop_recovery
                WHERE CASE WHEN the_day = life.dubai_today() THEN date <= the_day ELSE date = the_day END
                ORDER BY date DESC LIMIT 1
            ) r ON true
            LEFT JOIN LATERAL (
                SELECT * FROM health.whoop_sleep
                WHERE CASE WHEN the_day = life.dubai_today() THEN date <= the_day ELSE date = the_day END
                ORDER BY date DESC LIMIT 1
            ) s ON true
            LEFT JOIN LATERAL (
                SELECT * FROM health.whoop_strain
                WHERE CASE WHEN the_day = life.dubai_today() THEN date <= the_day ELSE date = the_day END
                ORDER BY date DESC LIMIT 1
            ) st ON true
            LEFT JOIN finance.transactions t ON t.date = the_day
            LEFT JOIN core.daily_summary ds ON ds.date = the_day
        GROUP BY
            r.recovery_score, r.hrv_rmssd, r.rhr, r.spo2,
            s.time_in_bed_min, s.awake_min, s.deep_sleep_min, s.rem_sleep_min, s.sleep_efficiency, s.sleep_performance,
            st.day_strain, st.calories_active,
            ds.meals_logged, ds.water_ml, ds.calories_consumed, ds.protein_g
        ON CONFLICT (day) DO UPDATE SET
            recovery_score = EXCLUDED.recovery_score,
            hrv = EXCLUDED.hrv,
            rhr = EXCLUDED.rhr,
            spo2 = EXCLUDED.spo2,
            sleep_minutes = EXCLUDED.sleep_minutes,
            deep_sleep_minutes = EXCLUDED.deep_sleep_minutes,
            rem_sleep_minutes = EXCLUDED.rem_sleep_minutes,
            sleep_efficiency = EXCLUDED.sleep_efficiency,
            sleep_performance = EXCLUDED.sleep_performance,
            sleep_hours = EXCLUDED.sleep_hours,
            deep_sleep_hours = EXCLUDED.deep_sleep_hours,
            strain = EXCLUDED.strain,
            calories_active = EXCLUDED.calories_active,
            weight_kg = EXCLUDED.weight_kg,
            spend_total = EXCLUDED.spend_total,
            spend_groceries = EXCLUDED.spend_groceries,
            spend_restaurants = EXCLUDED.spend_restaurants,
            spend_transport = EXCLUDED.spend_transport,
            income_total = EXCLUDED.income_total,
            transaction_count = EXCLUDED.transaction_count,
            meals_logged = EXCLUDED.meals_logged,
            water_ml = EXCLUDED.water_ml,
            calories_consumed = EXCLUDED.calories_consumed,
            protein_g = EXCLUDED.protein_g,
            data_completeness = EXCLUDED.data_completeness,
            computed_at = NOW();

        GET DIAGNOSTICS affected = ROW_COUNT;
        end_time := clock_timestamp();

        UPDATE ops.refresh_log
        SET ended_at = end_time,
            duration_ms = EXTRACT(MILLISECONDS FROM (end_time - start_time))::int,
            rows_affected = affected,
            status = 'success'
        WHERE id = log_id;

        PERFORM pg_advisory_unlock(lock_id);
        RETURN QUERY SELECT 'success'::TEXT, affected, EXTRACT(MILLISECONDS FROM (end_time - start_time))::int;

    EXCEPTION WHEN OTHERS THEN
        UPDATE ops.refresh_log
        SET ended_at = clock_timestamp(),
            status = 'error',
            error_message = SQLERRM
        WHERE id = log_id;
        PERFORM pg_advisory_unlock(lock_id);
        RAISE;
    END;
END;
$function$;
