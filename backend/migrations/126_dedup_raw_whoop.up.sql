-- Migration 126: Deduplicate raw WHOOP tables
-- Problem: Propagation triggers use NEW.id (auto-increment) as cycle_id/sleep_id/strain_id,
-- so each n8n poll creates a new raw row instead of upserting. Result: ~40x bloat.
-- Fix: Remove immutability triggers on raw.whoop_* (they prevent the upsert pattern),
-- dedup keeping latest per date, replace non-unique date indexes with unique ones,
-- rewrite trigger functions to upsert by date with correct column mappings.

BEGIN;

-- Step 1: Drop immutability triggers that block UPDATE/DELETE on raw.whoop_* tables.
-- These are no longer needed because the unique date index + upsert pattern prevents duplicates.
DROP TRIGGER IF EXISTS prevent_update_whoop_cycles ON raw.whoop_cycles;
DROP TRIGGER IF EXISTS prevent_update_whoop_sleep ON raw.whoop_sleep;
DROP TRIGGER IF EXISTS prevent_update_whoop_strain ON raw.whoop_strain;

-- Step 2: Dedup — keep only the latest row (highest id) per date
DELETE FROM raw.whoop_cycles
WHERE id NOT IN (
    SELECT MAX(id) FROM raw.whoop_cycles GROUP BY date
);

DELETE FROM raw.whoop_sleep
WHERE id NOT IN (
    SELECT MAX(id) FROM raw.whoop_sleep GROUP BY date
);

DELETE FROM raw.whoop_strain
WHERE id NOT IN (
    SELECT MAX(id) FROM raw.whoop_strain GROUP BY date
);

-- Step 3: Replace non-unique date indexes with unique constraints
DROP INDEX IF EXISTS raw.idx_raw_whoop_cycles_date;
DROP INDEX IF EXISTS raw.idx_raw_whoop_sleep_date;
DROP INDEX IF EXISTS raw.idx_raw_whoop_strain_date;
CREATE UNIQUE INDEX idx_raw_whoop_cycles_date ON raw.whoop_cycles (date);
CREATE UNIQUE INDEX idx_raw_whoop_sleep_date ON raw.whoop_sleep (date);
CREATE UNIQUE INDEX idx_raw_whoop_strain_date ON raw.whoop_strain (date);

-- Step 4: Rewrite propagation trigger functions to use ON CONFLICT (date) DO UPDATE
-- with correct column names matching actual raw.* and normalized.* schemas.

-- Recovery: health.whoop_recovery → raw.whoop_cycles → normalized.daily_recovery
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

    INSERT INTO normalized.daily_recovery (date, recovery_score, hrv, rhr, spo2, skin_temp_c, raw_id, source, updated_at)
    VALUES (NEW.date, NEW.recovery_score, NEW.hrv_rmssd, NEW.rhr, NEW.spo2, NEW.skin_temp, v_raw_id, 'whoop_api', NOW())
    ON CONFLICT (date) DO UPDATE SET
        recovery_score = EXCLUDED.recovery_score,
        hrv = EXCLUDED.hrv,
        rhr = EXCLUDED.rhr,
        spo2 = EXCLUDED.spo2,
        skin_temp_c = EXCLUDED.skin_temp_c,
        raw_id = EXCLUDED.raw_id,
        source = EXCLUDED.source,
        updated_at = NOW();

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
    VALUES ('propagate_whoop_recovery', TG_TABLE_NAME, SQLERRM, SQLSTATE);
    RAISE WARNING 'propagate_whoop_recovery failed for date %: % [%]', NEW.date, SQLERRM, SQLSTATE;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Sleep: health.whoop_sleep → raw.whoop_sleep → normalized.daily_sleep
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

    INSERT INTO normalized.daily_sleep (date, sleep_start, sleep_end, total_sleep_min, time_in_bed_min, light_sleep_min, deep_sleep_min, rem_sleep_min, awake_min, sleep_efficiency, sleep_performance, respiratory_rate, raw_id, source, updated_at)
    VALUES (
        NEW.date, NEW.sleep_start, NEW.sleep_end,
        COALESCE(NEW.time_in_bed_min, 0) - COALESCE(NEW.awake_min, 0),
        NEW.time_in_bed_min, NEW.light_sleep_min, NEW.deep_sleep_min,
        NEW.rem_sleep_min, NEW.awake_min, NEW.sleep_efficiency,
        NEW.sleep_performance, NEW.respiratory_rate, v_raw_id, 'whoop_api', NOW()
    )
    ON CONFLICT (date) DO UPDATE SET
        sleep_start = EXCLUDED.sleep_start,
        sleep_end = EXCLUDED.sleep_end,
        total_sleep_min = EXCLUDED.total_sleep_min,
        time_in_bed_min = EXCLUDED.time_in_bed_min,
        light_sleep_min = EXCLUDED.light_sleep_min,
        deep_sleep_min = EXCLUDED.deep_sleep_min,
        rem_sleep_min = EXCLUDED.rem_sleep_min,
        awake_min = EXCLUDED.awake_min,
        sleep_efficiency = EXCLUDED.sleep_efficiency,
        sleep_performance = EXCLUDED.sleep_performance,
        respiratory_rate = EXCLUDED.respiratory_rate,
        raw_id = EXCLUDED.raw_id,
        source = EXCLUDED.source,
        updated_at = NOW();

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
    VALUES ('propagate_whoop_sleep', TG_TABLE_NAME, SQLERRM, SQLSTATE);
    RAISE WARNING 'propagate_whoop_sleep failed for date %: % [%]', NEW.date, SQLERRM, SQLSTATE;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Strain: health.whoop_strain → raw.whoop_strain → normalized.daily_strain
CREATE OR REPLACE FUNCTION health.propagate_whoop_strain() RETURNS TRIGGER AS $$
DECLARE
    v_raw_id bigint;
BEGIN
    INSERT INTO raw.whoop_strain (strain_id, date, day_strain, workout_count, kilojoules, average_hr, max_hr, raw_json, source, ingested_at, run_id)
    VALUES (
        NEW.id, NEW.date, NEW.day_strain, 0,
        NEW.calories_total * 4.184, NEW.avg_hr, NEW.max_hr,
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
        raw_json = EXCLUDED.raw_json,
        ingested_at = NOW()
    RETURNING id INTO v_raw_id;

    INSERT INTO normalized.daily_strain (date, day_strain, calories_burned, calories_active, workout_count, average_hr, max_hr, raw_id, source, updated_at)
    VALUES (NEW.date, NEW.day_strain, NEW.calories_total, NEW.calories_active, 0, NEW.avg_hr, NEW.max_hr, v_raw_id, 'whoop_api', NOW())
    ON CONFLICT (date) DO UPDATE SET
        day_strain = EXCLUDED.day_strain,
        calories_burned = EXCLUDED.calories_burned,
        calories_active = EXCLUDED.calories_active,
        average_hr = EXCLUDED.average_hr,
        max_hr = EXCLUDED.max_hr,
        raw_id = EXCLUDED.raw_id,
        source = EXCLUDED.source,
        updated_at = NOW();

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
    VALUES ('propagate_whoop_strain', TG_TABLE_NAME, SQLERRM, SQLSTATE);
    RAISE WARNING 'propagate_whoop_strain failed for date %: % [%]', NEW.date, SQLERRM, SQLSTATE;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON INDEX raw.idx_raw_whoop_cycles_date IS 'Prevents duplicate raw.whoop_cycles per date. Added in migration 126 after dedup.';
COMMENT ON INDEX raw.idx_raw_whoop_sleep_date IS 'Prevents duplicate raw.whoop_sleep per date. Added in migration 126 after dedup.';
COMMENT ON INDEX raw.idx_raw_whoop_strain_date IS 'Prevents duplicate raw.whoop_strain per date. Added in migration 126 after dedup.';

COMMIT;
