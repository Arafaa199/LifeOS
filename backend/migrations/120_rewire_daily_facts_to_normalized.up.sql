-- Migration 120: Rewire life.refresh_daily_facts() to read from normalized layer only
--
-- BEFORE: Reads health.whoop_recovery, health.whoop_sleep, health.whoop_strain,
--         health.metrics, finance.transactions, facts.daily_nutrition, raw.reminders
-- AFTER:  Reads normalized.daily_recovery, normalized.daily_sleep, normalized.daily_strain,
--         normalized.body_metrics, normalized.v_daily_finance, normalized.food_log,
--         normalized.water_log, life.v_active_reminders
--
-- Also fixes: normalized.daily_strain missing calories_active column.
-- The trigger mapped calories_total → calories_burned, but daily_facts needs calories_active.

-- =============================================================================
-- 1. Add calories_active to normalized.daily_strain
-- =============================================================================

ALTER TABLE normalized.daily_strain
    ADD COLUMN IF NOT EXISTS calories_active INT;

-- Backfill from legacy table where possible
UPDATE normalized.daily_strain nst
SET calories_active = wst.calories_active
FROM health.whoop_strain wst
WHERE wst.date = nst.date
  AND nst.calories_active IS NULL;

-- =============================================================================
-- 2. Update propagation trigger to include calories_active
-- =============================================================================

CREATE OR REPLACE FUNCTION health.propagate_whoop_strain()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_raw_id bigint;
BEGIN
    INSERT INTO raw.whoop_strain (strain_id, date, day_strain, workout_count, kilojoules, average_hr, max_hr, raw_json, source, run_id)
    VALUES (
        NEW.id,
        NEW.date,
        NEW.day_strain,
        0,
        NEW.calories_total * 4.184,
        NEW.avg_hr,
        NEW.max_hr,
        COALESCE(NEW.raw_data, jsonb_build_object(
            'day_strain', NEW.day_strain,
            'calories_total', NEW.calories_total,
            'calories_active', NEW.calories_active,
            'propagated_at', now()
        )),
        'whoop_api',
        gen_random_uuid()
    )
    ON CONFLICT (strain_id) DO UPDATE SET
        day_strain = EXCLUDED.day_strain,
        kilojoules = EXCLUDED.kilojoules,
        average_hr = EXCLUDED.average_hr,
        max_hr = EXCLUDED.max_hr,
        raw_json = EXCLUDED.raw_json
    RETURNING id INTO v_raw_id;

    IF v_raw_id IS NOT NULL THEN
        INSERT INTO normalized.daily_strain (date, day_strain, calories_burned, calories_active, workout_count, average_hr, max_hr, raw_id, source)
        VALUES (NEW.date, NEW.day_strain, NEW.calories_total, NEW.calories_active, 0, NEW.avg_hr, NEW.max_hr, v_raw_id, 'whoop_api')
        ON CONFLICT (date) DO UPDATE SET
            day_strain = EXCLUDED.day_strain,
            calories_burned = EXCLUDED.calories_burned,
            calories_active = EXCLUDED.calories_active,
            average_hr = EXCLUDED.average_hr,
            max_hr = EXCLUDED.max_hr,
            raw_id = EXCLUDED.raw_id,
            source = EXCLUDED.source,
            updated_at = now();
    END IF;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
    VALUES ('propagate_whoop_strain', TG_TABLE_NAME, SQLERRM, SQLSTATE);
    RAISE WARNING 'propagate_whoop_strain failed: % [%]', SQLERRM, SQLSTATE;
    RETURN NEW;
END;
$fn$;

-- =============================================================================
-- 3. Rewire life.refresh_daily_facts() — normalized sources only
-- =============================================================================

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
            -- Health: Recovery
            recovery_score, hrv, rhr, spo2,
            -- Health: Sleep
            sleep_minutes, deep_sleep_minutes, rem_sleep_minutes, sleep_efficiency, sleep_performance,
            sleep_hours, deep_sleep_hours,
            -- Health: Strain
            strain, calories_active,
            -- Health: Body
            weight_kg,
            -- Finance
            spend_total, spend_groceries, spend_restaurants, spend_transport, income_total, transaction_count,
            -- Nutrition
            meals_logged, water_ml, calories_consumed, protein_g,
            -- Meta
            data_completeness, computed_at,
            -- Reminders
            reminders_due, reminders_completed
        )
        SELECT
            the_day,
            -- Recovery (from normalized.daily_recovery)
            nr.recovery_score,
            nr.hrv,
            nr.rhr,
            nr.spo2,
            -- Sleep (from normalized.daily_sleep)
            ns.time_in_bed_min - COALESCE(ns.awake_min, 0),
            ns.deep_sleep_min,
            ns.rem_sleep_min,
            ns.sleep_efficiency,
            ns.sleep_performance,
            ROUND((ns.time_in_bed_min - COALESCE(ns.awake_min, 0))::numeric / 60, 2),
            ROUND(ns.deep_sleep_min::numeric / 60, 2),
            -- Strain (from normalized.daily_strain)
            nst.day_strain,
            nst.calories_active,
            -- Weight (from normalized.body_metrics)
            nw.value,
            -- Finance (from normalized.v_daily_finance)
            COALESCE(nf.spend_total, 0),
            COALESCE(nf.spend_groceries, 0),
            COALESCE(nf.spend_restaurants, 0),
            COALESCE(nf.spend_transport, 0),
            COALESCE(nf.income_total, 0),
            COALESCE(nf.transaction_count, 0),
            -- Nutrition (from normalized.food_log + normalized.water_log)
            COALESCE(food.meals_logged, 0),
            COALESCE(water.water_ml, 0),
            food.calories_consumed,
            food.protein_g,
            -- Data completeness
            (
                CASE WHEN nr.recovery_score IS NOT NULL THEN 0.2 ELSE 0 END +
                CASE WHEN ns.time_in_bed_min IS NOT NULL THEN 0.2 ELSE 0 END +
                CASE WHEN nst.day_strain IS NOT NULL THEN 0.15 ELSE 0 END +
                CASE WHEN nw.value IS NOT NULL THEN 0.15 ELSE 0 END +
                CASE WHEN COALESCE(nf.transaction_count, 0) > 0 THEN 0.15 ELSE 0 END +
                CASE WHEN food.calories_consumed IS NOT NULL THEN 0.15 ELSE 0 END
            ),
            NOW(),
            -- Reminders (from life.v_active_reminders if available, raw.reminders fallback)
            COALESCE(rem.reminders_due, 0),
            COALESCE(rem.reminders_completed, 0)
        FROM
            (SELECT 1) AS dummy
            -- Recovery
            LEFT JOIN normalized.daily_recovery nr ON nr.date = the_day
            -- Sleep
            LEFT JOIN normalized.daily_sleep ns ON ns.date = the_day
            -- Strain
            LEFT JOIN normalized.daily_strain nst ON nst.date = the_day
            -- Weight: latest for the day
            LEFT JOIN LATERAL (
                SELECT value
                FROM normalized.body_metrics
                WHERE date = the_day AND metric_type = 'weight'
                ORDER BY recorded_at DESC LIMIT 1
            ) nw ON true
            -- Finance: pre-aggregated view
            LEFT JOIN normalized.v_daily_finance nf ON nf.date = the_day
            -- Nutrition: food
            LEFT JOIN LATERAL (
                SELECT
                    COUNT(DISTINCT meal_time)::INT AS meals_logged,
                    SUM(calories)::INT AS calories_consumed,
                    SUM(protein_g)::INT AS protein_g
                FROM normalized.food_log
                WHERE date = the_day
            ) food ON true
            -- Nutrition: water
            LEFT JOIN LATERAL (
                SELECT COALESCE(SUM(amount_ml), 0)::INT AS water_ml
                FROM normalized.water_log
                WHERE date = the_day
            ) water ON true
            -- Reminders
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
'Single-pipeline refresh. Reads ONLY from normalized layer:
- normalized.daily_recovery (WHOOP recovery)
- normalized.daily_sleep (WHOOP sleep)
- normalized.daily_strain (WHOOP strain)
- normalized.body_metrics (HealthKit weight)
- normalized.v_daily_finance (finance.transactions view)
- normalized.food_log (nutrition)
- normalized.water_log (hydration)
- raw.reminders (filtered by deleted_at IS NULL)
Advisory locked per day. Idempotent via ON CONFLICT.
Migration 120: Rewired from legacy tables to normalized.';
