-- Migration 121: Fix silent trigger failures
-- WHOOP propagation triggers currently catch exceptions and silently return NEW.
-- This means data can enter legacy health.whoop_* tables but fail to reach
-- raw.*/normalized.* — and nobody notices.
--
-- Fix: Add RAISE WARNING so failures appear in Postgres logs.
-- Keep RETURN NEW so legacy ingestion still succeeds.
-- ops.trigger_errors logging is already in place (from migration 094).

-- =============================================================================
-- 1. propagate_whoop_recovery — add RAISE WARNING
-- =============================================================================

CREATE OR REPLACE FUNCTION health.propagate_whoop_recovery()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
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
$fn$;

-- =============================================================================
-- 2. propagate_whoop_sleep — add RAISE WARNING
-- =============================================================================

CREATE OR REPLACE FUNCTION health.propagate_whoop_sleep()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
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
$fn$;

-- Note: propagate_whoop_strain was already updated in migration 120 with RAISE WARNING.

COMMENT ON FUNCTION health.propagate_whoop_recovery IS 'Propagates health.whoop_recovery → raw.whoop_cycles → normalized.daily_recovery. RAISE WARNING on failure (migration 121).';
COMMENT ON FUNCTION health.propagate_whoop_sleep IS 'Propagates health.whoop_sleep → raw.whoop_sleep → normalized.daily_sleep. RAISE WARNING on failure (migration 121).';
COMMENT ON FUNCTION health.propagate_whoop_strain IS 'Propagates health.whoop_strain → raw.whoop_strain → normalized.daily_strain. RAISE WARNING on failure (migration 120/121).';
