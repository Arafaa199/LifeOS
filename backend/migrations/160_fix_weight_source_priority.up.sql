-- Migration 160: Fix weight source priority in refresh_daily_facts
-- Problem: webhook source (stale HealthKit data) overwrites real scale readings
-- Solution: Prefer ha_eufy_scale > ios-app > webhook when multiple sources exist

-- Drop and recreate to allow signature change
DROP FUNCTION IF EXISTS life.refresh_daily_facts(DATE, TEXT);

-- Recreate with weight source priority fix
CREATE OR REPLACE FUNCTION life.refresh_daily_facts(target_day DATE DEFAULT NULL, triggered_by TEXT DEFAULT 'manual')
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
            workout_count, workout_minutes,
            spend_total, spend_groceries, spend_restaurants, spend_transport, income_total, transaction_count,
            meals_logged, water_ml, calories_consumed, protein_g,
            listening_minutes, listening_sessions,
            fasting_hours,
            data_completeness, computed_at,
            reminders_due, reminders_completed
        )
        SELECT
            the_day,
            rc.recovery_score, rc.hrv, rc.rhr, rc.spo2,
            (COALESCE(rs.time_in_bed_ms, 0) - COALESCE(rs.awake_ms, 0))::integer / 60000,
            rs.deep_sleep_ms::integer / 60000,
            rs.rem_sleep_ms::integer / 60000,
            rs.sleep_efficiency, rs.sleep_performance,
            ROUND((COALESCE(rs.time_in_bed_ms, 0) - COALESCE(rs.awake_ms, 0))::numeric / 3600000, 2),
            ROUND(COALESCE(rs.deep_sleep_ms, 0)::numeric / 3600000, 2),
            rst.day_strain, rst.calories,
            COALESCE(hkw.weight_kg, hmw.weight_kg),
            COALESCE(wo.workout_count, 0), COALESCE(wo.workout_minutes, 0),
            COALESCE(nf.spend_total, 0), COALESCE(nf.spend_groceries, 0),
            COALESCE(nf.spend_restaurants, 0), COALESCE(nf.spend_transport, 0),
            COALESCE(nf.income_total, 0), COALESCE(nf.transaction_count, 0),
            COALESCE(nfl.meals_logged, 0), COALESCE(nwl.water_ml, 0),
            nfl.calories_consumed, nfl.protein_g,
            COALESCE(mus.listening_minutes, 0), COALESCE(mus.listening_sessions, 0),
            COALESCE(fst.fasting_hours, 0),
            (
                CASE WHEN rc.recovery_score IS NOT NULL THEN 0.15 ELSE 0 END +
                CASE WHEN rs.time_in_bed_ms IS NOT NULL THEN 0.15 ELSE 0 END +
                CASE WHEN rst.day_strain IS NOT NULL THEN 0.10 ELSE 0 END +
                CASE WHEN COALESCE(hkw.weight_kg, hmw.weight_kg) IS NOT NULL THEN 0.08 ELSE 0 END +
                CASE WHEN COALESCE(nf.transaction_count, 0) > 0 THEN 0.12 ELSE 0 END +
                CASE WHEN COALESCE(nfl.meals_logged, 0) > 0 THEN 0.12 ELSE 0 END +
                CASE WHEN COALESCE(nwl.water_ml, 0) > 0 THEN 0.08 ELSE 0 END +
                CASE WHEN rem.reminders_due > 0 THEN 0.08 ELSE 0 END +
                CASE WHEN COALESCE(mus.listening_minutes, 0) > 0 THEN 0.04 ELSE 0 END +
                CASE WHEN COALESCE(fst.fasting_hours, 0) > 0 THEN 0.04 ELSE 0 END +
                CASE WHEN COALESCE(wo.workout_count, 0) > 0 THEN 0.04 ELSE 0 END
            ),
            NOW(),
            COALESCE(rem.reminders_due, 0), COALESCE(rem.reminders_completed, 0)
        FROM (SELECT the_day AS day) d
        LEFT JOIN LATERAL (
            SELECT recovery_score, hrv, rhr, spo2 FROM raw.whoop_cycles
            WHERE date = the_day ORDER BY ingested_at DESC LIMIT 1
        ) rc ON true
        LEFT JOIN LATERAL (
            SELECT time_in_bed_ms, awake_ms, deep_sleep_ms, rem_sleep_ms, sleep_efficiency, sleep_performance
            FROM raw.whoop_sleep WHERE date = the_day ORDER BY ingested_at DESC LIMIT 1
        ) rs ON true
        LEFT JOIN LATERAL (
            SELECT day_strain, calories_active AS calories FROM raw.whoop_strain
            WHERE date = the_day ORDER BY ingested_at DESC LIMIT 1
        ) rst ON true
        LEFT JOIN LATERAL (
            SELECT value AS weight_kg FROM raw.healthkit_samples
            WHERE sample_type = 'HKQuantityTypeIdentifierBodyMass'
              AND (start_date AT TIME ZONE 'Asia/Dubai')::date = the_day
            ORDER BY start_date DESC LIMIT 1
        ) hkw ON true
        -- FIX: Prioritize weight sources: ha_eufy_scale > ios-app > webhook
        -- This prevents stale HealthKit webhook data from overwriting real scale readings
        LEFT JOIN LATERAL (
            SELECT value AS weight_kg FROM health.metrics
            WHERE metric_type = 'weight' AND (recorded_at AT TIME ZONE 'Asia/Dubai')::date = the_day
            ORDER BY
                CASE source
                    WHEN 'ha_eufy_scale' THEN 1  -- Real scale reading (highest priority)
                    WHEN 'ios-app' THEN 2       -- Manual iOS app entry
                    WHEN 'webhook' THEN 3       -- HealthKit sync (often stale)
                    ELSE 4
                END,
                recorded_at DESC
            LIMIT 1
        ) hmw ON true
        LEFT JOIN LATERAL (
            SELECT COUNT(*)::int AS workout_count, COALESCE(SUM(duration_min), 0)::int AS workout_minutes
            FROM health.workouts WHERE (started_at AT TIME ZONE 'Asia/Dubai')::date = the_day
              AND source = 'healthkit'
        ) wo ON true
        LEFT JOIN LATERAL (
            SELECT spend_total, spend_groceries, spend_restaurants, spend_transport, income_total, transaction_count
            FROM finance.v_daily_finance WHERE date = the_day
        ) nf ON true
        LEFT JOIN LATERAL (
            SELECT COUNT(*)::int AS meals_logged, SUM(calories)::int AS calories_consumed, SUM(protein_g)::int AS protein_g
            FROM nutrition.food_log WHERE date = the_day
        ) nfl ON true
        LEFT JOIN LATERAL (
            SELECT SUM(amount_ml)::int AS water_ml FROM nutrition.water_log WHERE date = the_day
        ) nwl ON true
        LEFT JOIN LATERAL (
            SELECT
                COALESCE(SUM(EXTRACT(EPOCH FROM (ended_at - started_at)) / 60), 0)::int AS listening_minutes,
                COUNT(DISTINCT session_id)::int AS listening_sessions
            FROM life.listening_events
            WHERE (started_at AT TIME ZONE 'Asia/Dubai')::date = the_day
              AND ended_at IS NOT NULL
        ) mus ON true
        LEFT JOIN LATERAL (
            SELECT COALESCE(SUM(duration_hours), 0) AS fasting_hours
            FROM health.fasting_sessions
            WHERE (started_at AT TIME ZONE 'Asia/Dubai')::date = the_day
              AND ended_at IS NOT NULL
        ) fst ON true
        LEFT JOIN LATERAL (
            SELECT
                COUNT(*) FILTER (WHERE due_date = the_day)::int AS reminders_due,
                COUNT(*) FILTER (WHERE due_date = the_day AND is_completed)::int AS reminders_completed
            FROM raw.reminders
            WHERE due_date = the_day OR (due_date < the_day AND NOT is_completed)
        ) rem ON true
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
            workout_count = EXCLUDED.workout_count,
            workout_minutes = EXCLUDED.workout_minutes,
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
            listening_minutes = EXCLUDED.listening_minutes,
            listening_sessions = EXCLUDED.listening_sessions,
            fasting_hours = EXCLUDED.fasting_hours,
            data_completeness = EXCLUDED.data_completeness,
            computed_at = NOW(),
            reminders_due = EXCLUDED.reminders_due,
            reminders_completed = EXCLUDED.reminders_completed;

        GET DIAGNOSTICS affected = ROW_COUNT;

        end_time := clock_timestamp();

        UPDATE ops.refresh_log
        SET status = 'success',
            rows_affected = affected,
            duration_ms = EXTRACT(MILLISECONDS FROM end_time - start_time)::int,
            ended_at = end_time
        WHERE id = log_id;

        PERFORM pg_advisory_unlock(lock_id);

        RETURN QUERY SELECT 'success'::TEXT, affected, 0;

    EXCEPTION WHEN OTHERS THEN
        UPDATE ops.refresh_log
        SET status = 'failed',
            error_message = SQLERRM,
            ended_at = clock_timestamp()
        WHERE id = log_id;

        INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
        VALUES ('refresh_daily_facts', 'life.daily_facts', SQLERRM, SQLSTATE);

        PERFORM pg_advisory_unlock(lock_id);
        RAISE;
    END;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION life.refresh_daily_facts IS 'Rebuild daily_facts for a single day with source-prioritized weight selection';
