-- Migration 135: Deprecate normalized schema
--
-- The normalized layer was intended as a universal intermediate (raw → normalized → life.daily_facts),
-- but in practice only WHOOP data was ever populated via triggers. All other normalized tables
-- (transactions, food_log, water_log, body_metrics, mood_log) have 0 rows.
--
-- This migration:
--   1. Adds calories_active to raw.whoop_strain (was only in normalized.daily_strain)
--   2. Moves v_daily_finance to finance schema (it already reads finance.transactions)
--   3. Rewrites life.refresh_daily_facts() to read from raw.whoop_* directly
--   4. Rewrites facts.v_daily_health_timeseries to read from raw.whoop_* directly
--   5. Updates triggers to stop writing to normalized tables
--   6. Drops the entire normalized schema
--
-- New pipeline: health.whoop_* → raw.whoop_* → life.daily_facts (no intermediate)

BEGIN;

-- =============================================================================
-- 1. Add calories_active to raw.whoop_strain (previously only in normalized)
-- =============================================================================

ALTER TABLE raw.whoop_strain ADD COLUMN IF NOT EXISTS calories_active INT;

UPDATE raw.whoop_strain rs
SET calories_active = ws.calories_active
FROM health.whoop_strain ws
WHERE ws.date = rs.date
  AND rs.calories_active IS NULL;

-- =============================================================================
-- 2. Move v_daily_finance to finance schema
-- =============================================================================

CREATE OR REPLACE VIEW finance.v_daily_finance AS
WITH daily_category AS (
    SELECT
        finance.to_business_date(transaction_at) AS date,
        COALESCE(category, 'Uncategorized'::varchar) AS category,
        SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END) AS cat_spend,
        SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) AS cat_income,
        COUNT(*) AS cat_count
    FROM finance.transactions
    WHERE is_quarantined IS NOT TRUE
      AND pairing_role IS DISTINCT FROM 'fx_metadata'
      AND category NOT IN ('Transfer', 'CC Payment', 'BNPL Repayment', 'Credit Card Payment')
    GROUP BY finance.to_business_date(transaction_at), COALESCE(category, 'Uncategorized'::varchar)
)
SELECT
    date,
    COALESCE(SUM(cat_spend), 0) AS spend_total,
    COALESCE(SUM(cat_income), 0) AS income_total,
    SUM(cat_count)::integer AS transaction_count,
    COALESCE(SUM(CASE WHEN category = 'Groceries' THEN cat_spend END), 0) AS spend_groceries,
    COALESCE(SUM(CASE WHEN category IN ('Dining', 'Restaurants', 'Food Delivery') THEN cat_spend END), 0) AS spend_restaurants,
    COALESCE(SUM(CASE WHEN category = 'Transport' THEN cat_spend END), 0) AS spend_transport,
    jsonb_object_agg(category, cat_spend) FILTER (WHERE cat_spend > 0) AS spending_by_category
FROM daily_category
GROUP BY date;

COMMENT ON VIEW finance.v_daily_finance IS
'Daily finance aggregation. Reads finance.transactions, groups by business date.
Excludes quarantined, fx_metadata, and non-economic categories (Transfer, CC Payment, BNPL).
Moved from normalized schema in migration 135.';

-- =============================================================================
-- 3. Drop facts.v_daily_health_timeseries (depends on normalized tables)
-- =============================================================================

DROP VIEW IF EXISTS facts.v_daily_health_timeseries;

-- =============================================================================
-- 4. Recreate facts.v_daily_health_timeseries reading from raw
-- =============================================================================

CREATE VIEW facts.v_daily_health_timeseries AS
WITH healthkit_steps AS (
    SELECT (start_date AT TIME ZONE 'Asia/Dubai')::date AS date,
           COALESCE(SUM(value), 0)::integer AS steps
    FROM raw.healthkit_samples
    WHERE sample_type IN ('steps', 'HKQuantityTypeIdentifierStepCount')
    GROUP BY 1
), healthkit_active_energy AS (
    SELECT (start_date AT TIME ZONE 'Asia/Dubai')::date AS date,
           COALESCE(SUM(value), 0)::integer AS active_energy
    FROM raw.healthkit_samples
    WHERE sample_type IN ('active_energy', 'HKQuantityTypeIdentifierActiveEnergyBurned')
    GROUP BY 1
), healthkit_weight_raw AS (
    SELECT DISTINCT ON ((start_date AT TIME ZONE 'Asia/Dubai')::date)
           (start_date AT TIME ZONE 'Asia/Dubai')::date AS date,
           value AS weight_kg
    FROM raw.healthkit_samples
    WHERE sample_type IN ('weight', 'HKQuantityTypeIdentifierBodyMass')
    ORDER BY (start_date AT TIME ZONE 'Asia/Dubai')::date, start_date DESC
), healthkit_weight_legacy AS (
    SELECT DISTINCT ON (date) date, value AS weight_kg
    FROM health.metrics
    WHERE metric_type = 'weight'
    ORDER BY date, recorded_at DESC
), healthkit_weight AS (
    SELECT COALESCE(r.date, l.date) AS date,
           COALESCE(r.weight_kg, l.weight_kg) AS weight_kg
    FROM healthkit_weight_raw r
    FULL JOIN healthkit_weight_legacy l ON r.date = l.date
), date_series AS (
    SELECT generate_series(CURRENT_DATE - INTERVAL '90 days', CURRENT_DATE, '1 day')::date AS date
)
SELECT ds.date,
       rc.hrv,
       rc.rhr,
       rc.recovery_score AS recovery,
       (COALESCE(rs.light_sleep_ms, 0) + COALESCE(rs.deep_sleep_ms, 0) + COALESCE(rs.rem_sleep_ms, 0))::integer / 60000 AS sleep_minutes,
       rs.sleep_performance AS sleep_quality,
       rst.day_strain AS strain,
       COALESCE(hs.steps, 0) AS steps,
       hw.weight_kg AS weight,
       COALESCE(hae.active_energy, 0) AS active_energy,
       ROUND((
           CASE WHEN rc.recovery_score IS NOT NULL THEN 1 ELSE 0 END +
           CASE WHEN rc.hrv IS NOT NULL THEN 1 ELSE 0 END +
           CASE WHEN rs.light_sleep_ms IS NOT NULL THEN 1 ELSE 0 END +
           CASE WHEN rst.day_strain IS NOT NULL THEN 1 ELSE 0 END +
           CASE WHEN hs.steps > 0 THEN 1 ELSE 0 END +
           CASE WHEN hw.weight_kg IS NOT NULL THEN 1 ELSE 0 END
       )::numeric / 6.0, 2) AS coverage
FROM date_series ds
LEFT JOIN raw.whoop_cycles rc ON rc.date = ds.date
LEFT JOIN raw.whoop_sleep rs ON rs.date = ds.date
LEFT JOIN raw.whoop_strain rst ON rst.date = ds.date
LEFT JOIN healthkit_steps hs ON hs.date = ds.date
LEFT JOIN healthkit_active_energy hae ON hae.date = ds.date
LEFT JOIN healthkit_weight hw ON hw.date = ds.date
ORDER BY ds.date DESC;

-- =============================================================================
-- 5. Rewrite life.refresh_daily_facts() to read from raw directly
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
            -- Nutrition (no source tables exist yet — always NULL)
            meals_logged, water_ml, calories_consumed, protein_g,
            -- Meta
            data_completeness, computed_at,
            -- Reminders
            reminders_due, reminders_completed
        )
        SELECT
            the_day,
            -- Recovery (from raw.whoop_cycles — unique per date since migration 126)
            rc.recovery_score,
            rc.hrv,
            rc.rhr,
            rc.spo2,
            -- Sleep (from raw.whoop_sleep — ms converted to min)
            (COALESCE(rs.time_in_bed_ms, 0) - COALESCE(rs.awake_ms, 0))::integer / 60000,
            rs.deep_sleep_ms::integer / 60000,
            rs.rem_sleep_ms::integer / 60000,
            rs.sleep_efficiency,
            rs.sleep_performance,
            ROUND((COALESCE(rs.time_in_bed_ms, 0) - COALESCE(rs.awake_ms, 0))::numeric / 3600000, 2),
            ROUND(COALESCE(rs.deep_sleep_ms, 0)::numeric / 3600000, 2),
            -- Strain (from raw.whoop_strain)
            rst.day_strain,
            rst.calories_active,
            -- Weight (from health.metrics legacy table + raw.healthkit_samples)
            COALESCE(hkw.weight_kg, hmw.weight_kg),
            -- Finance (from finance.v_daily_finance — moved from normalized)
            COALESCE(nf.spend_total, 0),
            COALESCE(nf.spend_groceries, 0),
            COALESCE(nf.spend_restaurants, 0),
            COALESCE(nf.spend_transport, 0),
            COALESCE(nf.income_total, 0),
            COALESCE(nf.transaction_count, 0),
            -- Nutrition: no source tables exist yet, always 0/NULL
            0,  -- meals_logged
            0,  -- water_ml
            NULL,  -- calories_consumed
            NULL,  -- protein_g
            -- Data completeness
            (
                CASE WHEN rc.recovery_score IS NOT NULL THEN 0.2 ELSE 0 END +
                CASE WHEN rs.time_in_bed_ms IS NOT NULL THEN 0.2 ELSE 0 END +
                CASE WHEN rst.day_strain IS NOT NULL THEN 0.15 ELSE 0 END +
                CASE WHEN COALESCE(hkw.weight_kg, hmw.weight_kg) IS NOT NULL THEN 0.15 ELSE 0 END +
                CASE WHEN COALESCE(nf.transaction_count, 0) > 0 THEN 0.15 ELSE 0 END +
                0  -- nutrition not wired yet
            ),
            NOW(),
            -- Reminders (from raw.reminders)
            COALESCE(rem.reminders_due, 0),
            COALESCE(rem.reminders_completed, 0)
        FROM
            (SELECT 1) AS dummy
            -- Recovery: raw.whoop_cycles (one row per date, unique index)
            LEFT JOIN raw.whoop_cycles rc ON rc.date = the_day
            -- Sleep: raw.whoop_sleep (one row per date, unique index)
            LEFT JOIN raw.whoop_sleep rs ON rs.date = the_day
            -- Strain: raw.whoop_strain (one row per date, unique index)
            LEFT JOIN raw.whoop_strain rst ON rst.date = the_day
            -- Weight: HealthKit samples (latest per date)
            LEFT JOIN LATERAL (
                SELECT value AS weight_kg
                FROM raw.healthkit_samples
                WHERE sample_type IN ('weight', 'HKQuantityTypeIdentifierBodyMass')
                  AND (start_date AT TIME ZONE 'Asia/Dubai')::date = the_day
                ORDER BY start_date DESC LIMIT 1
            ) hkw ON true
            -- Weight: legacy health.metrics fallback
            LEFT JOIN LATERAL (
                SELECT value AS weight_kg
                FROM health.metrics
                WHERE date = the_day AND metric_type = 'weight'
                ORDER BY recorded_at DESC LIMIT 1
            ) hmw ON true
            -- Finance: aggregated view (now in finance schema)
            LEFT JOIN finance.v_daily_finance nf ON nf.date = the_day
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
'Single-pipeline refresh. Reads directly from raw layer + finance views:
- raw.whoop_cycles (recovery)
- raw.whoop_sleep (sleep, ms→min conversion)
- raw.whoop_strain (strain + calories_active)
- raw.healthkit_samples + health.metrics (weight)
- finance.v_daily_finance (spending/income aggregation)
- raw.reminders (filtered by deleted_at IS NULL)
Advisory locked per day. Idempotent via ON CONFLICT.
Migration 135: Rewired from normalized to raw (normalized schema dropped).';

-- =============================================================================
-- 6. Update triggers to stop writing to normalized tables
-- =============================================================================

-- Recovery: health.whoop_recovery → raw.whoop_cycles ONLY
CREATE OR REPLACE FUNCTION health.propagate_whoop_recovery() RETURNS TRIGGER AS $$
DECLARE
    v_raw_id bigint;
BEGIN
    INSERT INTO raw.whoop_cycles (cycle_id, date, recovery_score, hrv, rhr, spo2, skin_temp, raw_json, source, ingested_at, run_id)
    VALUES (
        NEW.id, NEW.date, NEW.recovery_score, NEW.hrv_rmssd, NEW.rhr, NEW.spo2, NEW.skin_temp,
        COALESCE(NEW.raw_data, jsonb_build_object(
            'recovery_score', NEW.recovery_score, 'hrv_rmssd', NEW.hrv_rmssd,
            'rhr', NEW.rhr, 'spo2', NEW.spo2, 'skin_temp', NEW.skin_temp,
            'sleep_performance', NEW.sleep_performance, 'propagated_at', now()
        )),
        'whoop_api', NOW(), gen_random_uuid()
    )
    ON CONFLICT (date) DO UPDATE SET
        cycle_id = EXCLUDED.cycle_id,
        recovery_score = EXCLUDED.recovery_score,
        hrv = EXCLUDED.hrv,
        rhr = EXCLUDED.rhr,
        spo2 = EXCLUDED.spo2,
        skin_temp = EXCLUDED.skin_temp,
        raw_json = EXCLUDED.raw_json,
        ingested_at = NOW()
    RETURNING id INTO v_raw_id;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
    VALUES ('propagate_whoop_recovery', TG_TABLE_NAME, SQLERRM, SQLSTATE);
    RAISE WARNING 'propagate_whoop_recovery failed for date %: % [%]', NEW.date, SQLERRM, SQLSTATE;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Sleep: health.whoop_sleep → raw.whoop_sleep ONLY
CREATE OR REPLACE FUNCTION health.propagate_whoop_sleep() RETURNS TRIGGER AS $$
DECLARE
    v_raw_id bigint;
BEGIN
    INSERT INTO raw.whoop_sleep (sleep_id, date, sleep_start, sleep_end, time_in_bed_ms, light_sleep_ms, deep_sleep_ms, rem_sleep_ms, awake_ms, sleep_efficiency, sleep_performance, respiratory_rate, raw_json, source, ingested_at, run_id)
    VALUES (
        NEW.id, NEW.date, NEW.sleep_start, NEW.sleep_end,
        NEW.time_in_bed_min * 60000, NEW.light_sleep_min * 60000,
        NEW.deep_sleep_min * 60000, NEW.rem_sleep_min * 60000,
        NEW.awake_min * 60000, NEW.sleep_efficiency, NEW.sleep_performance, NEW.respiratory_rate,
        COALESCE(NEW.raw_data, jsonb_build_object(
            'time_in_bed_min', NEW.time_in_bed_min, 'deep_sleep_min', NEW.deep_sleep_min,
            'rem_sleep_min', NEW.rem_sleep_min, 'light_sleep_min', NEW.light_sleep_min,
            'propagated_at', now()
        )),
        'whoop_api', NOW(), gen_random_uuid()
    )
    ON CONFLICT (date) DO UPDATE SET
        sleep_id = EXCLUDED.sleep_id,
        sleep_start = EXCLUDED.sleep_start,
        sleep_end = EXCLUDED.sleep_end,
        time_in_bed_ms = EXCLUDED.time_in_bed_ms,
        light_sleep_ms = EXCLUDED.light_sleep_ms,
        deep_sleep_ms = EXCLUDED.deep_sleep_ms,
        rem_sleep_ms = EXCLUDED.rem_sleep_ms,
        awake_ms = EXCLUDED.awake_ms,
        sleep_efficiency = EXCLUDED.sleep_efficiency,
        sleep_performance = EXCLUDED.sleep_performance,
        respiratory_rate = EXCLUDED.respiratory_rate,
        raw_json = EXCLUDED.raw_json,
        ingested_at = NOW()
    RETURNING id INTO v_raw_id;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
    VALUES ('propagate_whoop_sleep', TG_TABLE_NAME, SQLERRM, SQLSTATE);
    RAISE WARNING 'propagate_whoop_sleep failed for date %: % [%]', NEW.date, SQLERRM, SQLSTATE;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Strain: health.whoop_strain → raw.whoop_strain ONLY (now includes calories_active)
CREATE OR REPLACE FUNCTION health.propagate_whoop_strain() RETURNS TRIGGER AS $$
DECLARE
    v_raw_id bigint;
BEGIN
    INSERT INTO raw.whoop_strain (strain_id, date, day_strain, workout_count, kilojoules, average_hr, max_hr, calories_active, raw_json, source, ingested_at, run_id)
    VALUES (
        NEW.id, NEW.date, NEW.day_strain, 0,
        NEW.calories_total * 4.184, NEW.avg_hr, NEW.max_hr, NEW.calories_active,
        COALESCE(NEW.raw_data, jsonb_build_object(
            'day_strain', NEW.day_strain,
            'calories_total', NEW.calories_total,
            'calories_active', NEW.calories_active,
            'propagated_at', now()
        )),
        'whoop_api', NOW(), gen_random_uuid()
    )
    ON CONFLICT (date) DO UPDATE SET
        strain_id = EXCLUDED.strain_id,
        day_strain = EXCLUDED.day_strain,
        kilojoules = EXCLUDED.kilojoules,
        average_hr = EXCLUDED.average_hr,
        max_hr = EXCLUDED.max_hr,
        calories_active = EXCLUDED.calories_active,
        raw_json = EXCLUDED.raw_json,
        ingested_at = NOW()
    RETURNING id INTO v_raw_id;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
    VALUES ('propagate_whoop_strain', TG_TABLE_NAME, SQLERRM, SQLSTATE);
    RAISE WARNING 'propagate_whoop_strain failed for date %: % [%]', NEW.date, SQLERRM, SQLSTATE;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- 7. Drop normalized schema (CASCADE removes all tables, views, functions)
-- =============================================================================

DROP SCHEMA IF EXISTS normalized CASCADE;

-- =============================================================================
-- 8. Verify: refresh today's facts to confirm pipeline works without normalized
-- =============================================================================

SELECT * FROM life.refresh_daily_facts(life.dubai_today(), 'migration_135_verify');

COMMIT;
