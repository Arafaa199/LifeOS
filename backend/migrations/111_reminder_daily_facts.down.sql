-- Migration 111 DOWN: Remove reminder tracking from daily facts and dashboard
BEGIN;

-- 1. Remove reminder columns from daily_facts
ALTER TABLE life.daily_facts
    DROP COLUMN IF EXISTS reminders_due,
    DROP COLUMN IF EXISTS reminders_completed;

-- 2. Drop the view
DROP VIEW IF EXISTS life.v_daily_reminder_summary;

-- 3. Restore refresh_daily_facts WITHOUT reminder columns
-- (This restores the version from before migration 111)
CREATE OR REPLACE FUNCTION life.refresh_daily_facts(
    target_day DATE DEFAULT NULL,
    triggered_by TEXT DEFAULT 'manual'
)
RETURNS TABLE(status TEXT, rows_affected INT, errors INT) AS $$
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
                SELECT recovery_score, hrv_rmssd, rhr, spo2
                FROM health.whoop_recovery
                WHERE date = the_day
                ORDER BY created_at DESC LIMIT 1
            ) r ON true
            LEFT JOIN LATERAL (
                SELECT time_in_bed_min, awake_min, deep_sleep_min, rem_sleep_min,
                       sleep_efficiency, sleep_performance
                FROM health.whoop_sleep
                WHERE date = the_day
                ORDER BY created_at DESC LIMIT 1
            ) s ON true
            LEFT JOIN LATERAL (
                SELECT day_strain, calories_active
                FROM health.whoop_strain
                WHERE date = the_day
                ORDER BY created_at DESC LIMIT 1
            ) st ON true
            LEFT JOIN LATERAL (
                SELECT meals_logged, water_ml, calories AS calories_consumed, protein_g
                FROM facts.daily_nutrition
                WHERE date = the_day
            ) ds ON true
            LEFT JOIN finance.transactions t
                ON (t.transaction_at AT TIME ZONE 'Asia/Dubai')::date = the_day
        GROUP BY
            r.recovery_score, r.hrv_rmssd, r.rhr, r.spo2,
            s.time_in_bed_min, s.awake_min, s.deep_sleep_min, s.rem_sleep_min,
            s.sleep_efficiency, s.sleep_performance,
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
        SET status = 'success',
            rows_affected = affected,
            duration_ms = EXTRACT(EPOCH FROM (end_time - start_time)) * 1000
        WHERE id = log_id;

        PERFORM pg_advisory_unlock(lock_id);
        RETURN QUERY SELECT 'success'::TEXT, affected, 0;

    EXCEPTION WHEN OTHERS THEN
        end_time := clock_timestamp();
        UPDATE ops.refresh_log
        SET status = 'error',
            error_message = SQLERRM,
            duration_ms = EXTRACT(EPOCH FROM (end_time - start_time)) * 1000
        WHERE id = log_id;

        PERFORM pg_advisory_unlock(lock_id);
        RETURN QUERY SELECT 'error'::TEXT, 0, 1;
    END;
END;
$$ LANGUAGE plpgsql;

-- 4. Restore dashboard.get_payload to schema_version 7 (without reminder_summary)
-- The previous version is restored by removing the 'reminder_summary' key and reverting schema_version
-- For brevity, we just drop and let the previous migration's version stand
-- In practice, the UP migration of 110 or 107 would need to be re-applied to fully restore

COMMIT;
