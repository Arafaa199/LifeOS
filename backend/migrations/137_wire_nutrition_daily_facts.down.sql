-- Migration 137 Rollback: Revert nutrition wiring in daily_facts
--
-- Restores the hardcoded 0/NULL nutrition values from migration 135

BEGIN;

-- Restore the previous version of life.refresh_daily_facts() without nutrition aggregation
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
            -- Nutrition: hardcoded to 0/NULL (no source tables wired)
            0,
            0,
            NULL,
            NULL,
            (
                CASE WHEN rc.recovery_score IS NOT NULL THEN 0.2 ELSE 0 END +
                CASE WHEN rs.time_in_bed_ms IS NOT NULL THEN 0.2 ELSE 0 END +
                CASE WHEN rst.day_strain IS NOT NULL THEN 0.15 ELSE 0 END +
                CASE WHEN COALESCE(hkw.weight_kg, hmw.weight_kg) IS NOT NULL THEN 0.15 ELSE 0 END +
                CASE WHEN COALESCE(nf.transaction_count, 0) > 0 THEN 0.15 ELSE 0 END +
                0
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
            LEFT JOIN LATERAL (
                SELECT value AS weight_kg
                FROM health.metrics
                WHERE date = the_day AND metric_type = 'weight'
                ORDER BY recorded_at DESC LIMIT 1
            ) hmw ON true
            LEFT JOIN finance.v_daily_finance nf ON nf.date = the_day
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
'Single-pipeline refresh. Reads directly from raw layer + finance views:
- raw.whoop_cycles (recovery)
- raw.whoop_sleep (sleep, ms→min conversion)
- raw.whoop_strain (strain + calories_active)
- raw.healthkit_samples + health.metrics (weight)
- finance.v_daily_finance (spending/income aggregation)
- raw.reminders (filtered by deleted_at IS NULL)
Advisory locked per day. Idempotent via ON CONFLICT.
Migration 135: Rewired from normalized to raw (normalized schema dropped).';

-- Refresh to reset nutrition data
SELECT * FROM life.refresh_daily_facts(life.dubai_today(), 'migration_137_rollback');

COMMIT;
