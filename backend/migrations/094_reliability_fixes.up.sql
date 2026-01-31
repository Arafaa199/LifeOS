-- Migration 094: Data Reliability Fixes
-- Phase 1c: Define life.refresh_all()
-- Phase 2a: Feed status trigger for HealthKit weight (health.metrics)
-- Phase 2b: Trigger error logging (ops.trigger_errors + propagation rewrite)
-- Phase 2c: Expand get_payload() auto-refresh to check all sources
-- Phase 2d: WHOOP fallback in refresh_daily_facts (show latest data for today)

BEGIN;

-- ================================================
-- Phase 2b: ops.trigger_errors table
-- ================================================
CREATE TABLE IF NOT EXISTS ops.trigger_errors (
    id          BIGSERIAL PRIMARY KEY,
    trigger_name TEXT NOT NULL,
    table_name   TEXT NOT NULL,
    error_message TEXT,
    error_detail  TEXT,
    created_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_trigger_errors_created ON ops.trigger_errors (created_at DESC);

-- ================================================
-- Phase 1c: life.refresh_all(days, caller)
-- Refreshes daily_facts for last N days + all materialized views
-- ================================================
CREATE OR REPLACE FUNCTION life.refresh_all(
    p_days INTEGER DEFAULT 1,
    p_caller TEXT DEFAULT 'manual'
)
RETURNS JSONB
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_start DATE;
    v_end DATE;
    v_day DATE;
    v_refreshed INTEGER := 0;
    v_errors INTEGER := 0;
    v_result JSONB;
BEGIN
    v_end := life.dubai_today();
    v_start := v_end - (p_days - 1);

    -- Refresh daily_facts for each day
    FOR v_day IN SELECT generate_series(v_start, v_end, '1 day'::interval)::date
    LOOP
        BEGIN
            PERFORM life.refresh_daily_facts(v_day);
            v_refreshed := v_refreshed + 1;
        EXCEPTION WHEN OTHERS THEN
            v_errors := v_errors + 1;
            INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
            VALUES ('life.refresh_all', 'life.daily_facts',
                    SQLERRM, format('day=%s caller=%s', v_day, p_caller));
            RAISE NOTICE 'refresh_all: failed for % — %', v_day, SQLERRM;
        END;
    END LOOP;

    -- Refresh financial materialized views
    BEGIN
        PERFORM finance.refresh_financial_truth();
    EXCEPTION WHEN OTHERS THEN
        v_errors := v_errors + 1;
        INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
        VALUES ('life.refresh_all', 'finance.mv_*', SQLERRM, format('caller=%s', p_caller));
        RAISE NOTICE 'refresh_all: finance.refresh_financial_truth() failed — %', SQLERRM;
    END;

    v_result := jsonb_build_object(
        'refreshed_days', v_refreshed,
        'errors', v_errors,
        'range', format('%s..%s', v_start, v_end),
        'caller', p_caller,
        'completed_at', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
    );

    RAISE NOTICE 'refresh_all complete: %', v_result;
    RETURN v_result;
END;
$fn$;

-- ================================================
-- Phase 2a: Feed status trigger for HealthKit weight
-- health.metrics INSERT → update life.feed_status_live
-- ================================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'trg_feed_healthkit_metrics'
    ) THEN
        CREATE TRIGGER trg_feed_healthkit_metrics
            AFTER INSERT OR UPDATE ON health.metrics
            FOR EACH ROW
            EXECUTE FUNCTION life.update_feed_status('healthkit');
    END IF;
END $$;

-- Seed weight source if missing
INSERT INTO life.feed_status_live (source, last_event_at, events_today, last_updated)
VALUES ('weight',
    (SELECT MAX(recorded_at) FROM health.metrics WHERE metric_type = 'weight'),
    (SELECT COUNT(*) FROM health.metrics WHERE metric_type = 'weight'
        AND recorded_at::date = CURRENT_DATE),
    NOW()
)
ON CONFLICT (source) DO UPDATE SET
    last_event_at = EXCLUDED.last_event_at,
    events_today = EXCLUDED.events_today,
    last_updated = NOW();

-- ================================================
-- Phase 2b: Rewrite propagation triggers with error logging
-- ================================================

-- Recovery
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
EXCEPTION WHEN OTHERS THEN
    INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
    VALUES ('propagate_whoop_recovery', TG_TABLE_NAME, SQLERRM, SQLSTATE);
    RETURN NEW;
END;
$fn$;

-- Sleep
CREATE OR REPLACE FUNCTION health.propagate_whoop_sleep()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_raw_id bigint;
BEGIN
    INSERT INTO raw.whoop_sleep (sleep_id, date, sleep_start, sleep_end, time_in_bed_ms, light_sleep_ms, deep_sleep_ms, rem_sleep_ms, awake_ms, sleep_efficiency, sleep_performance, respiratory_rate, raw_json, source, run_id)
    VALUES (
        NEW.id,
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
EXCEPTION WHEN OTHERS THEN
    INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
    VALUES ('propagate_whoop_sleep', TG_TABLE_NAME, SQLERRM, SQLSTATE);
    RETURN NEW;
END;
$fn$;

-- Strain
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
EXCEPTION WHEN OTHERS THEN
    INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
    VALUES ('propagate_whoop_strain', TG_TABLE_NAME, SQLERRM, SQLSTATE);
    RETURN NEW;
END;
$fn$;

-- ================================================
-- Phase 2d: WHOOP fallback in refresh_daily_facts
-- For today: if no exact-date WHOOP data, show most recent available
-- For historical dates: exact match only (no contamination)
-- ================================================
CREATE OR REPLACE FUNCTION life.refresh_daily_facts(target_day date DEFAULT NULL::date, triggered_by character varying DEFAULT 'manual'::character varying)
 RETURNS TABLE(status text, rows_affected integer, duration_ms integer)
 LANGUAGE plpgsql
AS $function$
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
            strain, calories_active,
            weight_kg,
            spend_total, spend_groceries, spend_restaurants, spend_transport, income_total, transaction_count,
            meals_logged, water_ml, calories_consumed, protein_g,
            data_completeness, computed_at
        )
        SELECT
            the_day,
            r.recovery_score,
            r.hrv_rmssd,
            r.rhr,
            r.spo2,
            s.time_in_bed_min - COALESCE(s.awake_min, 0),
            s.deep_sleep_min,
            s.rem_sleep_min,
            s.sleep_efficiency,
            s.sleep_performance,
            st.day_strain,
            st.calories_active,
            (SELECT value FROM health.metrics
             WHERE metric_type = 'weight'
               AND life.to_dubai_date(recorded_at) = the_day
             ORDER BY recorded_at DESC LIMIT 1),
            COALESCE(ABS(SUM(CASE WHEN t.amount < 0 AND NOT t.is_quarantined THEN t.amount ELSE 0 END)), 0),
            COALESCE(ABS(SUM(CASE WHEN t.amount < 0 AND t.category = 'Groceries' AND NOT t.is_quarantined THEN t.amount ELSE 0 END)), 0),
            COALESCE(ABS(SUM(CASE WHEN t.amount < 0 AND t.category IN ('Dining', 'Restaurants', 'Food Delivery') AND NOT t.is_quarantined THEN t.amount ELSE 0 END)), 0),
            COALESCE(ABS(SUM(CASE WHEN t.amount < 0 AND t.category = 'Transport' AND NOT t.is_quarantined THEN t.amount ELSE 0 END)), 0),
            COALESCE(SUM(CASE WHEN t.amount > 0 AND NOT t.is_quarantined THEN t.amount ELSE 0 END), 0),
            COUNT(t.id) FILTER (WHERE NOT t.is_quarantined),
            COALESCE(ds.meals_logged, 0),
            COALESCE(ds.water_ml, 0),
            ds.calories_consumed,
            ds.protein_g,
            (
                CASE WHEN r.recovery_score IS NOT NULL THEN 0.2 ELSE 0 END +
                CASE WHEN s.time_in_bed_min IS NOT NULL THEN 0.2 ELSE 0 END +
                CASE WHEN st.day_strain IS NOT NULL THEN 0.15 ELSE 0 END +
                CASE WHEN EXISTS (SELECT 1 FROM health.metrics WHERE metric_type = 'weight' AND life.to_dubai_date(recorded_at) = the_day) THEN 0.15 ELSE 0 END +
                CASE WHEN COUNT(t.id) FILTER (WHERE NOT t.is_quarantined) > 0 THEN 0.15 ELSE 0 END +
                CASE WHEN ds.calories_consumed IS NOT NULL THEN 0.15 ELSE 0 END
            ),
            NOW()
        FROM
            (SELECT 1) AS dummy
            -- WHOOP: for today, fall back to most recent data if today's cycle not closed yet
            LEFT JOIN LATERAL (
                SELECT * FROM health.whoop_recovery
                WHERE CASE WHEN the_day = life.dubai_today() THEN date <= the_day ELSE date = the_day END
                ORDER BY date DESC LIMIT 1
            ) r ON true
            LEFT JOIN LATERAL (
                SELECT * FROM health.whoop_sleep
                WHERE CASE WHEN the_day = life.dubai_today() THEN date <= the_day ELSE date = the_day END
                ORDER BY date DESC LIMIT 1
            ) s ON true
            LEFT JOIN LATERAL (
                SELECT * FROM health.whoop_strain
                WHERE CASE WHEN the_day = life.dubai_today() THEN date <= the_day ELSE date = the_day END
                ORDER BY date DESC LIMIT 1
            ) st ON true
            LEFT JOIN finance.transactions t ON t.date = the_day
            LEFT JOIN core.daily_summary ds ON ds.date = the_day
        GROUP BY
            r.recovery_score, r.hrv_rmssd, r.rhr, r.spo2,
            s.time_in_bed_min, s.awake_min, s.deep_sleep_min, s.rem_sleep_min, s.sleep_efficiency, s.sleep_performance,
            st.day_strain, st.calories_active,
            ds.meals_logged, ds.water_ml, ds.calories_consumed, ds.protein_g
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
            computed_at = NOW();

        GET DIAGNOSTICS affected = ROW_COUNT;
        end_time := clock_timestamp();

        UPDATE ops.refresh_log
        SET ended_at = end_time,
            duration_ms = EXTRACT(MILLISECONDS FROM (end_time - start_time))::int,
            rows_affected = affected,
            status = 'success'
        WHERE id = log_id;

        PERFORM pg_advisory_unlock(lock_id);
        RETURN QUERY SELECT 'success'::TEXT, affected, EXTRACT(MILLISECONDS FROM (end_time - start_time))::int;

    EXCEPTION WHEN OTHERS THEN
        UPDATE ops.refresh_log
        SET ended_at = clock_timestamp(),
            status = 'error',
            error_message = SQLERRM
        WHERE id = log_id;
        PERFORM pg_advisory_unlock(lock_id);
        RAISE;
    END;
END;
$function$;

-- ================================================
-- Phase 2c: Expand get_payload() auto-refresh
-- Checks all sources including WHOOP fallback range for today
-- ================================================
CREATE OR REPLACE FUNCTION dashboard.get_payload(for_date date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    target_date DATE := COALESCE(for_date, life.dubai_today());
    payload JSONB;
    facts_computed TIMESTAMPTZ;
    source_latest TIMESTAMPTZ;
    is_today BOOLEAN;
BEGIN
    is_today := (target_date = life.dubai_today());

    -- Auto-refresh daily_facts if missing for target date
    IF NOT EXISTS (SELECT 1 FROM life.daily_facts WHERE day = target_date) THEN
        PERFORM life.refresh_daily_facts(target_date);
    ELSE
        -- Check if ANY source data is newer than last computation
        SELECT computed_at INTO facts_computed
        FROM life.daily_facts WHERE day = target_date;

        SELECT GREATEST(
            -- WHOOP: for today, also check most recent data (matches LATERAL fallback)
            (SELECT MAX(created_at) FROM health.whoop_recovery
             WHERE CASE WHEN is_today THEN date <= target_date ELSE date = target_date END),
            (SELECT MAX(created_at) FROM health.whoop_sleep
             WHERE CASE WHEN is_today THEN date <= target_date ELSE date = target_date END),
            (SELECT MAX(created_at) FROM health.whoop_strain
             WHERE CASE WHEN is_today THEN date <= target_date ELSE date = target_date END),
            -- HealthKit weight
            (SELECT MAX(recorded_at) FROM health.metrics
             WHERE metric_type = 'weight'
               AND (recorded_at AT TIME ZONE 'Asia/Dubai')::date = target_date),
            -- Finance transactions
            (SELECT MAX(created_at) FROM finance.transactions
             WHERE (transaction_at AT TIME ZONE 'Asia/Dubai')::date = target_date)
        ) INTO source_latest;

        -- Re-refresh if any source data arrived after last computation
        IF source_latest IS NOT NULL AND (facts_computed IS NULL OR source_latest > facts_computed) THEN
            PERFORM life.refresh_daily_facts(target_date);
        END IF;
    END IF;

    -- Payload assembly uses existing views (same as migration 093)
    SELECT jsonb_build_object(
        'meta', jsonb_build_object(
            'schema_version', 5,
            'generated_at', to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
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
            SELECT jsonb_agg(
                jsonb_build_object(
                    'feed', f.feed,
                    'status', f.status,
                    'last_sync', to_char(f.last_sync AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                    'total_records', f.total_records,
                    'hours_since_sync', f.hours_since_sync
                )
            )
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
                        'last_sync', to_char(MAX(last_sync) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
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
                        'last_sync', to_char(last_sync AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
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
                'generated_at', to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
            )
        ),
        'domains_status', (
            SELECT COALESCE(jsonb_agg(
                jsonb_build_object(
                    'domain', d.domain,
                    'status', d.status,
                    'as_of', d.as_of,
                    'last_success', d.last_success,
                    'last_error', d.last_error
                )
            ), '[]'::jsonb)
            FROM ops.v_domains_status d
        )
    ) INTO payload;

    RETURN payload;
END;
$function$;

COMMIT;
