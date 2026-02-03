-- Migration 138 Rollback: Revert weight source priority
--
-- Reverts to timestamp-only ordering for weight (migration 137 behavior).
-- NOTE: Deleted test data is NOT restored.

BEGIN;

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
            data_completeness, computed_at,
            reminders_due, reminders_completed
        )
        SELECT
            the_day,
            rc.recovery_score,
            rc.hrv,
            rc.rhr,
            rc.spo2,
            (COALESCE(rs.time_in_bed_ms, 0) - COALESCE(rs.awake_ms, 0))::integer / 60000,
            rs.deep_sleep_ms::integer / 60000,
            rs.rem_sleep_ms::integer / 60000,
            rs.sleep_efficiency,
            rs.sleep_performance,
            ROUND((COALESCE(rs.time_in_bed_ms, 0) - COALESCE(rs.awake_ms, 0))::numeric / 3600000, 2),
            ROUND(COALESCE(rs.deep_sleep_ms, 0)::numeric / 3600000, 2),
            rst.day_strain,
            rst.calories_active,
            COALESCE(hkw.weight_kg, hmw.weight_kg),
            COALESCE(nf.spend_total, 0),
            COALESCE(nf.spend_groceries, 0),
            COALESCE(nf.spend_restaurants, 0),
            COALESCE(nf.spend_transport, 0),
            COALESCE(nf.income_total, 0),
            COALESCE(nf.transaction_count, 0),
            COALESCE(nfl.meals_logged, 0),
            COALESCE(nwl.water_ml, 0),
            nfl.calories_consumed,
            nfl.protein_g,
            (
                CASE WHEN rc.recovery_score IS NOT NULL THEN 0.18 ELSE 0 END +
                CASE WHEN rs.time_in_bed_ms IS NOT NULL THEN 0.18 ELSE 0 END +
                CASE WHEN rst.day_strain IS NOT NULL THEN 0.12 ELSE 0 END +
                CASE WHEN COALESCE(hkw.weight_kg, hmw.weight_kg) IS NOT NULL THEN 0.12 ELSE 0 END +
                CASE WHEN COALESCE(nf.transaction_count, 0) > 0 THEN 0.15 ELSE 0 END +
                CASE WHEN COALESCE(nfl.meals_logged, 0) > 0 THEN 0.15 ELSE 0 END +
                CASE WHEN COALESCE(nwl.water_ml, 0) > 0 THEN 0.10 ELSE 0 END
            ),
            NOW(),
            COALESCE(rem.reminders_due, 0),
            COALESCE(rem.reminders_completed, 0)
        FROM
            (SELECT 1) AS dummy
            LEFT JOIN raw.whoop_cycles rc ON rc.date = the_day
            LEFT JOIN raw.whoop_sleep rs ON rs.date = the_day
            LEFT JOIN raw.whoop_strain rst ON rst.date = the_day
            LEFT JOIN LATERAL (
                SELECT value AS weight_kg
                FROM raw.healthkit_samples
                WHERE sample_type IN ('weight', 'HKQuantityTypeIdentifierBodyMass')
                  AND (start_date AT TIME ZONE 'Asia/Dubai')::date = the_day
                ORDER BY start_date DESC LIMIT 1
            ) hkw ON true
            -- Weight: legacy health.metrics (timestamp-only, no source priority - reverted)
            LEFT JOIN LATERAL (
                SELECT value AS weight_kg
                FROM health.metrics
                WHERE date = the_day AND metric_type = 'weight'
                ORDER BY recorded_at DESC LIMIT 1
            ) hmw ON true
            LEFT JOIN finance.v_daily_finance nf ON nf.date = the_day
            LEFT JOIN LATERAL (
                SELECT
                    COUNT(*)::int AS meals_logged,
                    SUM(calories)::int AS calories_consumed,
                    SUM(protein_g)::numeric(6,1) AS protein_g
                FROM nutrition.food_log
                WHERE (logged_at AT TIME ZONE 'Asia/Dubai')::date = the_day
            ) nfl ON true
            LEFT JOIN LATERAL (
                SELECT SUM(amount_ml)::int AS water_ml
                FROM nutrition.water_log
                WHERE date = the_day
            ) nwl ON true
            LEFT JOIN LATERAL (
                SELECT
                    COUNT(*) FILTER (WHERE due_date IS NOT NULL AND (due_date AT TIME ZONE 'Asia/Dubai')::date = the_day) AS reminders_due,
                    COUNT(*) FILTER (WHERE is_completed = true AND completed_date IS NOT NULL AND (completed_date AT TIME ZONE 'Asia/Dubai')::date = the_day) AS reminders_completed
                FROM raw.reminders
                WHERE deleted_at IS NULL
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
            computed_at = NOW(),
            reminders_due = EXCLUDED.reminders_due,
            reminders_completed = EXCLUDED.reminders_completed;

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
        RAISE WARNING 'refresh_daily_facts failed for %: % [%]', the_day, SQLERRM, SQLSTATE;
        RETURN QUERY SELECT 'error'::TEXT, 0, 1;
    END;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION life.refresh_daily_facts IS
'Single-pipeline refresh with nutrition support. Reads directly from raw layer + nutrition.
Migration 137: Added nutrition aggregation from food_log + water_log.';

COMMIT;
