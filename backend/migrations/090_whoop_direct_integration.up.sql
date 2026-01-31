-- Migration: 090_whoop_direct_integration
-- Purpose: Support direct WHOOP API integration (bypass Home Assistant)
-- Changes:
--   1. Update propagation trigger source from 'home_assistant' to 'whoop_api'
--   2. Add feed_status triggers for sleep and strain tables
--   3. Update get_payload() to re-refresh daily_facts when source data is newer
-- Created: 2026-01-29

-- ============================================================
-- 1. Update propagation triggers to use 'whoop_api' source
--    and handle the DELETE+INSERT pattern properly
-- ============================================================

-- Recovery propagation: uses INSERT trigger (DELETE+INSERT in workflow ensures this fires)
CREATE OR REPLACE FUNCTION health.propagate_whoop_recovery()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_raw_id bigint;
BEGIN
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
        'whoop_api',
        gen_random_uuid()
    )
    ON CONFLICT (cycle_id) DO UPDATE SET
        recovery_score = EXCLUDED.recovery_score,
        hrv = EXCLUDED.hrv,
        rhr = EXCLUDED.rhr,
        spo2 = EXCLUDED.spo2,
        skin_temp = EXCLUDED.skin_temp,
        raw_json = EXCLUDED.raw_json
    RETURNING id INTO v_raw_id;

    IF v_raw_id IS NOT NULL THEN
        INSERT INTO normalized.daily_recovery (date, recovery_score, hrv, rhr, spo2, skin_temp_c, raw_id, source)
        VALUES (NEW.date, NEW.recovery_score, NEW.hrv_rmssd, NEW.rhr, NEW.spo2, NEW.skin_temp, v_raw_id, 'whoop_api')
        ON CONFLICT (date) DO UPDATE SET
            recovery_score = EXCLUDED.recovery_score,
            hrv = EXCLUDED.hrv,
            rhr = EXCLUDED.rhr,
            spo2 = EXCLUDED.spo2,
            skin_temp_c = EXCLUDED.skin_temp_c,
            raw_id = EXCLUDED.raw_id,
            source = EXCLUDED.source,
            updated_at = now();
    END IF;

    RETURN NEW;
END;
$fn$;

-- Sleep propagation
CREATE OR REPLACE FUNCTION health.propagate_whoop_sleep()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_raw_id bigint;
BEGIN
    INSERT INTO raw.whoop_sleep (sleep_id, date, sleep_start, sleep_end, time_in_bed_ms, light_sleep_ms, deep_sleep_ms, rem_sleep_ms, awake_ms, sleep_efficiency, sleep_performance, respiratory_rate, raw_json, source, run_id)
    VALUES (
        NEW.id::text,
        NEW.date,
        NEW.sleep_start,
        NEW.sleep_end,
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
            'deep_sleep_min', NEW.deep_sleep_min,
            'rem_sleep_min', NEW.rem_sleep_min,
            'light_sleep_min', NEW.light_sleep_min,
            'propagated_at', now()
        )),
        'whoop_api',
        gen_random_uuid()
    )
    ON CONFLICT (sleep_id) DO UPDATE SET
        time_in_bed_ms = EXCLUDED.time_in_bed_ms,
        light_sleep_ms = EXCLUDED.light_sleep_ms,
        deep_sleep_ms = EXCLUDED.deep_sleep_ms,
        rem_sleep_ms = EXCLUDED.rem_sleep_ms,
        awake_ms = EXCLUDED.awake_ms,
        sleep_efficiency = EXCLUDED.sleep_efficiency,
        sleep_performance = EXCLUDED.sleep_performance,
        respiratory_rate = EXCLUDED.respiratory_rate,
        raw_json = EXCLUDED.raw_json
    RETURNING id INTO v_raw_id;

    IF v_raw_id IS NOT NULL THEN
        INSERT INTO normalized.daily_sleep (date, sleep_start, sleep_end, total_sleep_min, time_in_bed_min, light_sleep_min, deep_sleep_min, rem_sleep_min, awake_min, sleep_efficiency, sleep_performance, respiratory_rate, raw_id, source)
        VALUES (
            NEW.date, NEW.sleep_start, NEW.sleep_end,
            COALESCE(NEW.time_in_bed_min, 0) - COALESCE(NEW.awake_min, 0),
            NEW.time_in_bed_min, NEW.light_sleep_min, NEW.deep_sleep_min, NEW.rem_sleep_min, NEW.awake_min,
            NEW.sleep_efficiency, NEW.sleep_performance, NEW.respiratory_rate,
            v_raw_id, 'whoop_api'
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
            updated_at = now();
    END IF;

    RETURN NEW;
END;
$fn$;

-- Strain propagation
CREATE OR REPLACE FUNCTION health.propagate_whoop_strain()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_raw_id bigint;
BEGIN
    INSERT INTO raw.whoop_strain (strain_id, date, day_strain, workout_count, kilojoules, average_hr, max_hr, raw_json, source, run_id)
    VALUES (
        NEW.id::text,
        NEW.date,
        NEW.day_strain,
        0,
        NEW.calories_total * 4.184,
        NEW.avg_hr,
        NEW.max_hr,
        COALESCE(NEW.raw_data, jsonb_build_object(
            'day_strain', NEW.day_strain,
            'calories_total', NEW.calories_total,
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
        INSERT INTO normalized.daily_strain (date, day_strain, calories_burned, workout_count, average_hr, max_hr, raw_id, source)
        VALUES (NEW.date, NEW.day_strain, NEW.calories_total, 0, NEW.avg_hr, NEW.max_hr, v_raw_id, 'whoop_api')
        ON CONFLICT (date) DO UPDATE SET
            day_strain = EXCLUDED.day_strain,
            calories_burned = EXCLUDED.calories_burned,
            average_hr = EXCLUDED.average_hr,
            max_hr = EXCLUDED.max_hr,
            raw_id = EXCLUDED.raw_id,
            source = EXCLUDED.source,
            updated_at = now();
    END IF;

    RETURN NEW;
END;
$fn$;

-- ============================================================
-- 2. Add feed_status triggers for sleep and strain
--    (recovery already has one, sleep and strain don't)
-- ============================================================

-- Feed status update for sleep
CREATE OR REPLACE FUNCTION life.update_feed_status_sleep()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
    INSERT INTO ops.feed_events (feed, event_type, event_at)
    VALUES ('whoop_sleep', 'sync', now())
    ON CONFLICT DO NOTHING;
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$fn$;

CREATE OR REPLACE FUNCTION life.update_feed_status_strain()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
    INSERT INTO ops.feed_events (feed, event_type, event_at)
    VALUES ('whoop_strain', 'sync', now())
    ON CONFLICT DO NOTHING;
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$fn$;

-- Only create triggers if they don't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_feed_whoop_sleep' AND tgrelid = 'health.whoop_sleep'::regclass) THEN
        CREATE TRIGGER trg_feed_whoop_sleep
            AFTER INSERT ON health.whoop_sleep
            FOR EACH ROW EXECUTE FUNCTION life.update_feed_status_sleep();
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_feed_whoop_strain' AND tgrelid = 'health.whoop_strain'::regclass) THEN
        CREATE TRIGGER trg_feed_whoop_strain
            AFTER INSERT ON health.whoop_strain
            FOR EACH ROW EXECUTE FUNCTION life.update_feed_status_strain();
    END IF;
END $$;

-- ============================================================
-- 3. Update get_payload() to re-refresh stale daily_facts
--    If WHOOP data arrived after last computed_at, re-refresh
-- ============================================================

CREATE OR REPLACE FUNCTION dashboard.get_payload(for_date date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    target_date DATE := COALESCE(for_date, life.dubai_today());
    payload JSONB;
    facts_computed TIMESTAMPTZ;
    whoop_latest TIMESTAMPTZ;
BEGIN
    -- Auto-refresh daily_facts if missing for target date
    IF NOT EXISTS (SELECT 1 FROM life.daily_facts WHERE day = target_date) THEN
        PERFORM life.refresh_daily_facts(target_date);
    ELSE
        -- Check if source data is newer than last computation
        SELECT computed_at INTO facts_computed
        FROM life.daily_facts WHERE day = target_date;

        SELECT GREATEST(
            (SELECT MAX(created_at) FROM health.whoop_recovery WHERE date = target_date),
            (SELECT MAX(created_at) FROM health.whoop_sleep WHERE date = target_date),
            (SELECT MAX(created_at) FROM health.whoop_strain WHERE date = target_date)
        ) INTO whoop_latest;

        -- Re-refresh if WHOOP data arrived after last computation
        IF whoop_latest IS NOT NULL AND (facts_computed IS NULL OR whoop_latest > facts_computed) THEN
            PERFORM life.refresh_daily_facts(target_date);
        END IF;
    END IF;

    SELECT jsonb_build_object(
        'meta', jsonb_build_object(
            'schema_version', 4,
            'generated_at', NOW(),
            'for_date', target_date,
            'timezone', 'Asia/Dubai'
        ),
        'today_facts', (
            SELECT to_jsonb(t.*) - 'schema_version' - 'generated_at' - 'for_date'
            FROM dashboard.v_today t
        ),
        'trends', (
            SELECT jsonb_agg(to_jsonb(t.*) - 'schema_version' - 'generated_at')
            FROM dashboard.v_trends t
        ),
        'feed_status', (
            SELECT jsonb_agg(to_jsonb(f.*))
            FROM ops.feed_status f
        ),
        'recent_events', (
            SELECT COALESCE(jsonb_agg(to_jsonb(e.*)), '[]'::jsonb)
            FROM dashboard.v_recent_events e
        ),
        'stale_feeds', (
            SELECT COALESCE(jsonb_agg(feed), '[]'::jsonb)
            FROM ops.feed_status
            WHERE status IN ('stale', 'critical')
        ),
        'daily_insights', jsonb_build_object(
            'alerts', (
                SELECT COALESCE(jsonb_agg(jsonb_build_object(
                    'alert_type', alert_type,
                    'severity', severity,
                    'description', description
                )), '[]'::jsonb)
                FROM insights.cross_domain_alerts
                WHERE day = target_date
            ),
            'patterns', (
                SELECT COALESCE(jsonb_agg(jsonb_build_object(
                    'day_name', day_name,
                    'pattern_flag', pattern_flag,
                    'avg_spend', avg_spend,
                    'avg_recovery', avg_recovery,
                    'sample_size', sample_size,
                    'days_with_spend', days_with_spend,
                    'confidence', confidence
                )), '[]'::jsonb)
                FROM insights.pattern_detector
                WHERE pattern_flag != 'normal'
                  AND confidence != 'low'
            ),
            'spending_by_recovery', (
                SELECT COALESCE(jsonb_agg(jsonb_build_object(
                    'recovery_level', recovery_level,
                    'days', days,
                    'days_with_spend', days_with_spend,
                    'avg_spend', avg_spend,
                    'confidence', confidence
                )), '[]'::jsonb)
                FROM insights.spending_by_recovery_level
                WHERE confidence != 'low'
            ),
            'today_is', (
                SELECT pattern_flag
                FROM insights.pattern_detector
                WHERE day_name = to_char(target_date, 'FMDay')
                  AND sample_size >= 7
            ),
            'ranked_insights', insights.get_ranked_insights(target_date)
        ),
        'data_freshness', (
            SELECT jsonb_build_object(
                'health', (
                    SELECT jsonb_build_object(
                        'status', CASE
                            WHEN bool_or(status = 'critical') THEN 'critical'
                            WHEN bool_or(status = 'stale') THEN 'stale'
                            ELSE 'healthy'
                        END,
                        'last_sync', MAX(last_sync),
                        'hours_since_sync', ROUND(MIN(hours_since_sync)::numeric, 1),
                        'stale_feeds', COALESCE(
                            jsonb_agg(feed) FILTER (WHERE status IN ('stale', 'critical')),
                            '[]'::jsonb
                        )
                    )
                    FROM ops.feed_status
                    WHERE feed IN ('whoop_recovery', 'whoop_sleep', 'whoop_strain', 'weight')
                ),
                'finance', (
                    SELECT jsonb_build_object(
                        'status', COALESCE(status, 'unknown'),
                        'last_sync', last_sync,
                        'hours_since_sync', ROUND(hours_since_sync::numeric, 1),
                        'stale_feeds', CASE
                            WHEN status IN ('stale', 'critical') THEN jsonb_build_array(feed)
                            ELSE '[]'::jsonb
                        END
                    )
                    FROM ops.feed_status
                    WHERE feed = 'transactions'
                ),
                'overall_status', (
                    SELECT CASE
                        WHEN bool_or(status = 'critical') THEN 'critical'
                        WHEN bool_or(status = 'stale') THEN 'stale'
                        ELSE 'healthy'
                    END
                    FROM ops.feed_status
                ),
                'generated_at', NOW()
            )
        )
    ) INTO payload;

    RETURN payload;
END;
$function$;

COMMENT ON FUNCTION dashboard.get_payload(date) IS
'Dashboard payload with auto-refresh: re-refreshes daily_facts when WHOOP source data is newer than last computation';
