-- Migration 085: Wire WHOOP legacy tables to raw.* and normalized.* layers
-- Purpose: Backfill existing health.whoop_* data into the raw/normalized pipeline
--          and add triggers to auto-propagate future inserts.
--
-- Data flow: health.whoop_* (legacy, n8n writes here)
--         -> raw.whoop_* (immutable raw layer)
--         -> normalized.daily_* (deduplicated, one row per date)

BEGIN;

-- ============================================================
-- 1. Backfill raw.whoop_cycles from health.whoop_recovery
-- ============================================================
INSERT INTO raw.whoop_cycles (cycle_id, date, recovery_score, hrv, rhr, spo2, skin_temp, raw_json, source, run_id)
SELECT
    wr.id AS cycle_id,
    wr.date,
    wr.recovery_score,
    wr.hrv_rmssd,
    wr.rhr,
    wr.spo2,
    wr.skin_temp,
    COALESCE(wr.raw_data, jsonb_build_object(
        'recovery_score', wr.recovery_score,
        'hrv_rmssd', wr.hrv_rmssd,
        'rhr', wr.rhr,
        'spo2', wr.spo2,
        'skin_temp', wr.skin_temp,
        'sleep_performance', wr.sleep_performance,
        'backfilled_from', 'health.whoop_recovery',
        'backfilled_at', now()
    )) AS raw_json,
    'home_assistant' AS source,
    '00000000-0000-0000-0000-000000000085'::uuid AS run_id
FROM health.whoop_recovery wr
ON CONFLICT (cycle_id) DO NOTHING;

-- ============================================================
-- 2. Backfill raw.whoop_sleep from health.whoop_sleep
-- ============================================================
INSERT INTO raw.whoop_sleep (sleep_id, date, sleep_start, sleep_end, time_in_bed_ms, light_sleep_ms, deep_sleep_ms, rem_sleep_ms, awake_ms, sleep_efficiency, sleep_performance, respiratory_rate, raw_json, source, run_id)
SELECT
    ws.id AS sleep_id,
    ws.date,
    ws.sleep_start::timestamptz,
    ws.sleep_end::timestamptz,
    ws.time_in_bed_min * 60000,
    ws.light_sleep_min * 60000,
    ws.deep_sleep_min * 60000,
    ws.rem_sleep_min * 60000,
    ws.awake_min * 60000,
    ws.sleep_efficiency,
    ws.sleep_performance,
    ws.respiratory_rate,
    COALESCE(ws.raw_data, jsonb_build_object(
        'time_in_bed_min', ws.time_in_bed_min,
        'awake_min', ws.awake_min,
        'light_sleep_min', ws.light_sleep_min,
        'deep_sleep_min', ws.deep_sleep_min,
        'rem_sleep_min', ws.rem_sleep_min,
        'sleep_efficiency', ws.sleep_efficiency,
        'sleep_performance', ws.sleep_performance,
        'respiratory_rate', ws.respiratory_rate,
        'backfilled_from', 'health.whoop_sleep',
        'backfilled_at', now()
    )) AS raw_json,
    'home_assistant' AS source,
    '00000000-0000-0000-0000-000000000085'::uuid AS run_id
FROM health.whoop_sleep ws
ON CONFLICT (sleep_id) DO NOTHING;

-- ============================================================
-- 3. Backfill raw.whoop_strain from health.whoop_strain
-- ============================================================
INSERT INTO raw.whoop_strain (strain_id, date, day_strain, workout_count, kilojoules, average_hr, max_hr, raw_json, source, run_id)
SELECT
    wst.id AS strain_id,
    wst.date,
    wst.day_strain,
    NULL AS workout_count,  -- health.whoop_strain doesn't have this
    wst.calories_total * 4.184,  -- approximate kcal to kJ conversion
    wst.avg_hr,
    wst.max_hr,
    COALESCE(wst.raw_data, jsonb_build_object(
        'day_strain', wst.day_strain,
        'max_hr', wst.max_hr,
        'avg_hr', wst.avg_hr,
        'calories_total', wst.calories_total,
        'calories_active', wst.calories_active,
        'backfilled_from', 'health.whoop_strain',
        'backfilled_at', now()
    )) AS raw_json,
    'home_assistant' AS source,
    '00000000-0000-0000-0000-000000000085'::uuid AS run_id
FROM health.whoop_strain wst
ON CONFLICT (strain_id) DO NOTHING;

-- ============================================================
-- 4. Backfill normalized.daily_recovery from raw.whoop_cycles
-- ============================================================
INSERT INTO normalized.daily_recovery (date, recovery_score, hrv, rhr, spo2, skin_temp_c, raw_id, source)
SELECT
    rc.date,
    rc.recovery_score,
    rc.hrv,
    rc.rhr,
    rc.spo2,
    rc.skin_temp,
    rc.id AS raw_id,
    rc.source
FROM raw.whoop_cycles rc
ON CONFLICT (date) DO UPDATE SET
    recovery_score = EXCLUDED.recovery_score,
    hrv = EXCLUDED.hrv,
    rhr = EXCLUDED.rhr,
    spo2 = EXCLUDED.spo2,
    skin_temp_c = EXCLUDED.skin_temp_c,
    raw_id = EXCLUDED.raw_id,
    source = EXCLUDED.source;

-- ============================================================
-- 5. Backfill normalized.daily_sleep from raw.whoop_sleep
-- ============================================================
INSERT INTO normalized.daily_sleep (date, sleep_start, sleep_end, total_sleep_min, time_in_bed_min, light_sleep_min, deep_sleep_min, rem_sleep_min, awake_min, sleep_efficiency, sleep_performance, respiratory_rate, raw_id, source)
SELECT
    rs.date,
    rs.sleep_start,
    rs.sleep_end,
    (rs.light_sleep_ms + rs.deep_sleep_ms + rs.rem_sleep_ms) / 60000 AS total_sleep_min,
    rs.time_in_bed_ms / 60000 AS time_in_bed_min,
    rs.light_sleep_ms / 60000,
    rs.deep_sleep_ms / 60000,
    rs.rem_sleep_ms / 60000,
    rs.awake_ms / 60000,
    rs.sleep_efficiency,
    rs.sleep_performance,
    rs.respiratory_rate,
    rs.id AS raw_id,
    rs.source
FROM raw.whoop_sleep rs
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
    source = EXCLUDED.source;

-- ============================================================
-- 6. Backfill normalized.daily_strain from raw.whoop_strain
-- ============================================================
INSERT INTO normalized.daily_strain (date, day_strain, calories_burned, workout_count, average_hr, max_hr, raw_id, source)
SELECT
    rst.date,
    rst.day_strain,
    (rst.kilojoules / 4.184)::integer AS calories_burned,  -- kJ back to kcal
    rst.workout_count,
    rst.average_hr,
    rst.max_hr,
    rst.id AS raw_id,
    rst.source
FROM raw.whoop_strain rst
ON CONFLICT (date) DO UPDATE SET
    day_strain = EXCLUDED.day_strain,
    calories_burned = EXCLUDED.calories_burned,
    workout_count = EXCLUDED.workout_count,
    average_hr = EXCLUDED.average_hr,
    max_hr = EXCLUDED.max_hr,
    raw_id = EXCLUDED.raw_id,
    source = EXCLUDED.source;

-- ============================================================
-- 7. Create function to propagate health.whoop_recovery → raw → normalized
-- ============================================================
CREATE OR REPLACE FUNCTION health.propagate_whoop_recovery()
RETURNS TRIGGER AS $$
DECLARE
    v_raw_id bigint;
BEGIN
    -- Insert into raw.whoop_cycles
    INSERT INTO raw.whoop_cycles (cycle_id, date, recovery_score, hrv, rhr, spo2, skin_temp, raw_json, source, run_id)
    VALUES (
        NEW.id,
        NEW.date,
        NEW.recovery_score,
        NEW.hrv_rmssd,
        NEW.rhr,
        NEW.spo2,
        NEW.skin_temp,
        COALESCE(NEW.raw_data, jsonb_build_object(
            'recovery_score', NEW.recovery_score,
            'hrv_rmssd', NEW.hrv_rmssd,
            'rhr', NEW.rhr,
            'spo2', NEW.spo2,
            'skin_temp', NEW.skin_temp,
            'sleep_performance', NEW.sleep_performance,
            'propagated_at', now()
        )),
        'home_assistant',
        gen_random_uuid()
    )
    ON CONFLICT (cycle_id) DO NOTHING
    RETURNING id INTO v_raw_id;

    -- If inserted (not a duplicate), propagate to normalized
    IF v_raw_id IS NOT NULL THEN
        INSERT INTO normalized.daily_recovery (date, recovery_score, hrv, rhr, spo2, skin_temp_c, raw_id, source)
        VALUES (NEW.date, NEW.recovery_score, NEW.hrv_rmssd, NEW.rhr, NEW.spo2, NEW.skin_temp, v_raw_id, 'home_assistant')
        ON CONFLICT (date) DO UPDATE SET
            recovery_score = EXCLUDED.recovery_score,
            hrv = EXCLUDED.hrv,
            rhr = EXCLUDED.rhr,
            spo2 = EXCLUDED.spo2,
            skin_temp_c = EXCLUDED.skin_temp_c,
            raw_id = EXCLUDED.raw_id,
            source = EXCLUDED.source;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 8. Create function to propagate health.whoop_sleep → raw → normalized
-- ============================================================
CREATE OR REPLACE FUNCTION health.propagate_whoop_sleep()
RETURNS TRIGGER AS $$
DECLARE
    v_raw_id bigint;
    v_total_sleep_min integer;
BEGIN
    -- Insert into raw.whoop_sleep
    INSERT INTO raw.whoop_sleep (sleep_id, date, sleep_start, sleep_end, time_in_bed_ms, light_sleep_ms, deep_sleep_ms, rem_sleep_ms, awake_ms, sleep_efficiency, sleep_performance, respiratory_rate, raw_json, source, run_id)
    VALUES (
        NEW.id,
        NEW.date,
        NEW.sleep_start::timestamptz,
        NEW.sleep_end::timestamptz,
        NEW.time_in_bed_min * 60000,
        NEW.light_sleep_min * 60000,
        NEW.deep_sleep_min * 60000,
        NEW.rem_sleep_min * 60000,
        NEW.awake_min * 60000,
        NEW.sleep_efficiency,
        NEW.sleep_performance,
        NEW.respiratory_rate,
        COALESCE(NEW.raw_data, jsonb_build_object(
            'time_in_bed_min', NEW.time_in_bed_min,
            'light_sleep_min', NEW.light_sleep_min,
            'deep_sleep_min', NEW.deep_sleep_min,
            'rem_sleep_min', NEW.rem_sleep_min,
            'awake_min', NEW.awake_min,
            'sleep_efficiency', NEW.sleep_efficiency,
            'sleep_performance', NEW.sleep_performance,
            'propagated_at', now()
        )),
        'home_assistant',
        gen_random_uuid()
    )
    ON CONFLICT (sleep_id) DO NOTHING
    RETURNING id INTO v_raw_id;

    IF v_raw_id IS NOT NULL THEN
        v_total_sleep_min := COALESCE(NEW.light_sleep_min, 0) + COALESCE(NEW.deep_sleep_min, 0) + COALESCE(NEW.rem_sleep_min, 0);

        INSERT INTO normalized.daily_sleep (date, sleep_start, sleep_end, total_sleep_min, time_in_bed_min, light_sleep_min, deep_sleep_min, rem_sleep_min, awake_min, sleep_efficiency, sleep_performance, respiratory_rate, raw_id, source)
        VALUES (NEW.date, NEW.sleep_start::timestamptz, NEW.sleep_end::timestamptz, v_total_sleep_min, NEW.time_in_bed_min, NEW.light_sleep_min, NEW.deep_sleep_min, NEW.rem_sleep_min, NEW.awake_min, NEW.sleep_efficiency, NEW.sleep_performance, NEW.respiratory_rate, v_raw_id, 'home_assistant')
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
            raw_id = EXCLUDED.raw_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 9. Create function to propagate health.whoop_strain → raw → normalized
-- ============================================================
CREATE OR REPLACE FUNCTION health.propagate_whoop_strain()
RETURNS TRIGGER AS $$
DECLARE
    v_raw_id bigint;
BEGIN
    INSERT INTO raw.whoop_strain (strain_id, date, day_strain, workout_count, kilojoules, average_hr, max_hr, raw_json, source, run_id)
    VALUES (
        NEW.id,
        NEW.date,
        NEW.day_strain,
        NULL,
        CASE WHEN NEW.calories_total IS NOT NULL THEN NEW.calories_total * 4.184 END,
        NEW.avg_hr,
        NEW.max_hr,
        COALESCE(NEW.raw_data, jsonb_build_object(
            'day_strain', NEW.day_strain,
            'max_hr', NEW.max_hr,
            'avg_hr', NEW.avg_hr,
            'calories_total', NEW.calories_total,
            'calories_active', NEW.calories_active,
            'propagated_at', now()
        )),
        'home_assistant',
        gen_random_uuid()
    )
    ON CONFLICT (strain_id) DO NOTHING
    RETURNING id INTO v_raw_id;

    IF v_raw_id IS NOT NULL THEN
        INSERT INTO normalized.daily_strain (date, day_strain, calories_burned, workout_count, average_hr, max_hr, raw_id, source)
        VALUES (NEW.date, NEW.day_strain, NEW.calories_total, NULL, NEW.avg_hr, NEW.max_hr, v_raw_id, 'home_assistant')
        ON CONFLICT (date) DO UPDATE SET
            day_strain = EXCLUDED.day_strain,
            calories_burned = EXCLUDED.calories_burned,
            average_hr = EXCLUDED.average_hr,
            max_hr = EXCLUDED.max_hr,
            raw_id = EXCLUDED.raw_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 10. Create triggers on health.whoop_* tables
-- ============================================================
CREATE TRIGGER propagate_recovery_to_normalized
    AFTER INSERT ON health.whoop_recovery
    FOR EACH ROW
    EXECUTE FUNCTION health.propagate_whoop_recovery();

CREATE TRIGGER propagate_sleep_to_normalized
    AFTER INSERT ON health.whoop_sleep
    FOR EACH ROW
    EXECUTE FUNCTION health.propagate_whoop_sleep();

CREATE TRIGGER propagate_strain_to_normalized
    AFTER INSERT ON health.whoop_strain
    FOR EACH ROW
    EXECUTE FUNCTION health.propagate_whoop_strain();

COMMIT;
