-- Revert migration 124: Restore triggers to INSERT-only and original function bodies

BEGIN;

-- Restore original recovery function (single BEGIN/EXCEPTION, no nested block)
CREATE OR REPLACE FUNCTION health.propagate_whoop_recovery() RETURNS TRIGGER AS $$
DECLARE
    v_raw_id bigint;
BEGIN
    INSERT INTO raw.whoop_cycles (cycle_id, date, recovery_score, hrv, rhr, spo2, skin_temp, raw_json, source, run_id)
    VALUES (
        NEW.id, NEW.date, NEW.recovery_score, NEW.hrv_rmssd, NEW.rhr, NEW.spo2, NEW.skin_temp,
        COALESCE(NEW.raw_data, jsonb_build_object(
            'recovery_score', NEW.recovery_score, 'hrv_rmssd', NEW.hrv_rmssd,
            'rhr', NEW.rhr, 'spo2', NEW.spo2, 'skin_temp', NEW.skin_temp,
            'sleep_performance', NEW.sleep_performance, 'propagated_at', now()
        )),
        'whoop_api', gen_random_uuid()
    )
    ON CONFLICT (cycle_id) DO UPDATE SET
        recovery_score = EXCLUDED.recovery_score, hrv = EXCLUDED.hrv,
        rhr = EXCLUDED.rhr, spo2 = EXCLUDED.spo2,
        skin_temp = EXCLUDED.skin_temp, raw_json = EXCLUDED.raw_json
    RETURNING id INTO v_raw_id;

    IF v_raw_id IS NOT NULL THEN
        INSERT INTO normalized.daily_recovery (date, recovery_score, hrv, rhr, spo2, skin_temp_c, raw_id, source)
        VALUES (NEW.date, NEW.recovery_score, NEW.hrv_rmssd, NEW.rhr, NEW.spo2, NEW.skin_temp, v_raw_id, 'whoop_api')
        ON CONFLICT (date) DO UPDATE SET
            recovery_score = EXCLUDED.recovery_score, hrv = EXCLUDED.hrv,
            rhr = EXCLUDED.rhr, spo2 = EXCLUDED.spo2,
            skin_temp_c = EXCLUDED.skin_temp_c, raw_id = EXCLUDED.raw_id,
            source = EXCLUDED.source, updated_at = now();
    END IF;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
    VALUES ('propagate_whoop_recovery', TG_TABLE_NAME, SQLERRM, SQLSTATE);
    RAISE WARNING 'propagate_whoop_recovery failed: % [%]', SQLERRM, SQLSTATE;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Restore original sleep function
CREATE OR REPLACE FUNCTION health.propagate_whoop_sleep() RETURNS TRIGGER AS $$
DECLARE
    v_raw_id bigint;
BEGIN
    INSERT INTO raw.whoop_sleep (sleep_id, date, sleep_start, sleep_end, time_in_bed_ms, light_sleep_ms, deep_sleep_ms, rem_sleep_ms, awake_ms, sleep_efficiency, sleep_performance, respiratory_rate, raw_json, source, run_id)
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
        'whoop_api', gen_random_uuid()
    )
    ON CONFLICT (sleep_id) DO UPDATE SET
        time_in_bed_ms = EXCLUDED.time_in_bed_ms, light_sleep_ms = EXCLUDED.light_sleep_ms,
        deep_sleep_ms = EXCLUDED.deep_sleep_ms, rem_sleep_ms = EXCLUDED.rem_sleep_ms,
        awake_ms = EXCLUDED.awake_ms, sleep_efficiency = EXCLUDED.sleep_efficiency,
        sleep_performance = EXCLUDED.sleep_performance, respiratory_rate = EXCLUDED.respiratory_rate,
        raw_json = EXCLUDED.raw_json
    RETURNING id INTO v_raw_id;

    IF v_raw_id IS NOT NULL THEN
        INSERT INTO normalized.daily_sleep (date, sleep_start, sleep_end, total_sleep_min, time_in_bed_min, light_sleep_min, deep_sleep_min, rem_sleep_min, awake_min, sleep_efficiency, sleep_performance, respiratory_rate, raw_id, source)
        VALUES (
            NEW.date, NEW.sleep_start, NEW.sleep_end,
            COALESCE(NEW.time_in_bed_min, 0) - COALESCE(NEW.awake_min, 0),
            NEW.time_in_bed_min, NEW.light_sleep_min, NEW.deep_sleep_min,
            NEW.rem_sleep_min, NEW.awake_min, NEW.sleep_efficiency,
            NEW.sleep_performance, NEW.respiratory_rate, v_raw_id, 'whoop_api'
        )
        ON CONFLICT (date) DO UPDATE SET
            sleep_start = EXCLUDED.sleep_start, sleep_end = EXCLUDED.sleep_end,
            total_sleep_min = EXCLUDED.total_sleep_min, time_in_bed_min = EXCLUDED.time_in_bed_min,
            light_sleep_min = EXCLUDED.light_sleep_min, deep_sleep_min = EXCLUDED.deep_sleep_min,
            rem_sleep_min = EXCLUDED.rem_sleep_min, awake_min = EXCLUDED.awake_min,
            sleep_efficiency = EXCLUDED.sleep_efficiency, sleep_performance = EXCLUDED.sleep_performance,
            respiratory_rate = EXCLUDED.respiratory_rate, raw_id = EXCLUDED.raw_id,
            source = EXCLUDED.source, updated_at = now();
    END IF;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
    VALUES ('propagate_whoop_sleep', TG_TABLE_NAME, SQLERRM, SQLSTATE);
    RAISE WARNING 'propagate_whoop_sleep failed: % [%]', SQLERRM, SQLSTATE;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Restore original strain function
CREATE OR REPLACE FUNCTION health.propagate_whoop_strain() RETURNS TRIGGER AS $$
DECLARE
    v_raw_id bigint;
BEGIN
    INSERT INTO raw.whoop_strain (strain_id, date, day_strain, workout_count, kilojoules, average_hr, max_hr, raw_json, source, run_id)
    VALUES (
        NEW.id, NEW.date, NEW.day_strain, 0,
        NEW.calories_total * 4.184, NEW.avg_hr, NEW.max_hr,
        COALESCE(NEW.raw_data, jsonb_build_object(
            'day_strain', NEW.day_strain,
            'calories_total', NEW.calories_total,
            'calories_active', NEW.calories_active,
            'propagated_at', now()
        )),
        'whoop_api', gen_random_uuid()
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
$$ LANGUAGE plpgsql;

-- Restore triggers to INSERT-only
DROP TRIGGER IF EXISTS propagate_recovery_to_normalized ON health.whoop_recovery;
CREATE TRIGGER propagate_recovery_to_normalized
    AFTER INSERT ON health.whoop_recovery
    FOR EACH ROW
    EXECUTE FUNCTION health.propagate_whoop_recovery();

DROP TRIGGER IF EXISTS propagate_sleep_to_normalized ON health.whoop_sleep;
CREATE TRIGGER propagate_sleep_to_normalized
    AFTER INSERT ON health.whoop_sleep
    FOR EACH ROW
    EXECUTE FUNCTION health.propagate_whoop_sleep();

DROP TRIGGER IF EXISTS propagate_strain_to_normalized ON health.whoop_strain;
CREATE TRIGGER propagate_strain_to_normalized
    AFTER INSERT ON health.whoop_strain
    FOR EACH ROW
    EXECUTE FUNCTION health.propagate_whoop_strain();

COMMIT;
