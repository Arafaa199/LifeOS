-- Migration 111: Reminder-based task completion tracking
-- Creates daily reminder summary view, adds columns to daily_facts,
-- wires into refresh pipeline, and adds to dashboard payload.

BEGIN;

-- 0. Drop old VARCHAR overload of refresh_daily_facts (conflicts with TEXT version)
DROP FUNCTION IF EXISTS life.refresh_daily_facts(date, character varying);

-- 1. Create view: daily reminder summary from raw.reminders
CREATE OR REPLACE VIEW life.v_daily_reminder_summary AS
SELECT
    d.day,
    -- Reminders due on this day
    COALESCE(due.cnt, 0) AS reminders_due,
    -- Reminders completed on this day (by completed_date)
    COALESCE(comp.cnt, 0) AS reminders_completed,
    -- Reminders overdue as of this day (due before this day, still not completed)
    COALESCE(overdue.cnt, 0) AS reminders_overdue,
    -- Completion rate for reminders due on this day
    CASE
        WHEN COALESCE(due.cnt, 0) = 0 THEN NULL
        ELSE ROUND(COALESCE(comp_for_due.cnt, 0)::numeric / due.cnt, 2)
    END AS completion_rate
FROM (
    -- Generate days from earliest reminder activity to today
    SELECT generate_series(
        LEAST(
            (SELECT MIN((due_date AT TIME ZONE 'Asia/Dubai')::date) FROM raw.reminders WHERE due_date IS NOT NULL),
            (SELECT MIN((completed_date AT TIME ZONE 'Asia/Dubai')::date) FROM raw.reminders WHERE completed_date IS NOT NULL)
        ),
        (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Dubai')::date,
        '1 day'::interval
    )::date AS day
) d
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS cnt
    FROM raw.reminders
    WHERE due_date IS NOT NULL
      AND (due_date AT TIME ZONE 'Asia/Dubai')::date = d.day
) due ON true
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS cnt
    FROM raw.reminders
    WHERE is_completed = true
      AND completed_date IS NOT NULL
      AND (completed_date AT TIME ZONE 'Asia/Dubai')::date = d.day
) comp ON true
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS cnt
    FROM raw.reminders
    WHERE due_date IS NOT NULL
      AND (due_date AT TIME ZONE 'Asia/Dubai')::date < d.day
      AND (is_completed = false OR is_completed IS NULL)
) overdue ON true
LEFT JOIN LATERAL (
    -- Completed reminders that were due on this specific day
    SELECT COUNT(*) AS cnt
    FROM raw.reminders
    WHERE due_date IS NOT NULL
      AND (due_date AT TIME ZONE 'Asia/Dubai')::date = d.day
      AND is_completed = true
) comp_for_due ON true
WHERE COALESCE(due.cnt, 0) > 0
   OR COALESCE(comp.cnt, 0) > 0;

-- 2. Add reminder columns to life.daily_facts
ALTER TABLE life.daily_facts
    ADD COLUMN IF NOT EXISTS reminders_due INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS reminders_completed INTEGER DEFAULT 0;

-- 3. Update life.refresh_daily_facts to populate reminder columns
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
            r.recovery_score,
            r.hrv_rmssd,
            r.rhr,
            r.spo2,
            s.time_in_bed_min - COALESCE(s.awake_min, 0),
            s.deep_sleep_min,
            s.rem_sleep_min,
            s.sleep_efficiency,
            s.sleep_performance,
            ROUND((s.time_in_bed_min - COALESCE(s.awake_min, 0))::numeric / 60, 2),
            ROUND(s.deep_sleep_min::numeric / 60, 2),
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
            NOW(),
            -- Reminder columns
            COALESCE(rem.reminders_due, 0),
            COALESCE(rem.reminders_completed, 0)
        FROM
            (SELECT 1) AS dummy
            LEFT JOIN LATERAL (
                SELECT recovery_score, hrv_rmssd, rhr, spo2
                FROM health.whoop_recovery
                WHERE date = the_day
                ORDER BY created_at DESC LIMIT 1
            ) r ON true
            LEFT JOIN LATERAL (
                SELECT time_in_bed_min, awake_min, deep_sleep_min, rem_sleep_min,
                       sleep_efficiency, sleep_performance
                FROM health.whoop_sleep
                WHERE date = the_day
                ORDER BY created_at DESC LIMIT 1
            ) s ON true
            LEFT JOIN LATERAL (
                SELECT day_strain, calories_active
                FROM health.whoop_strain
                WHERE date = the_day
                ORDER BY created_at DESC LIMIT 1
            ) st ON true
            LEFT JOIN LATERAL (
                SELECT meals_logged, water_ml, calories AS calories_consumed, protein_g
                FROM facts.daily_nutrition
                WHERE date = the_day
            ) ds ON true
            LEFT JOIN LATERAL (
                SELECT
                    COUNT(*) FILTER (WHERE due_date IS NOT NULL AND (due_date AT TIME ZONE 'Asia/Dubai')::date = the_day) AS reminders_due,
                    COUNT(*) FILTER (WHERE is_completed = true AND completed_date IS NOT NULL AND (completed_date AT TIME ZONE 'Asia/Dubai')::date = the_day) AS reminders_completed
                FROM raw.reminders
            ) rem ON true
            LEFT JOIN finance.transactions t
                ON (t.transaction_at AT TIME ZONE 'Asia/Dubai')::date = the_day
        GROUP BY
            r.recovery_score, r.hrv_rmssd, r.rhr, r.spo2,
            s.time_in_bed_min, s.awake_min, s.deep_sleep_min, s.rem_sleep_min,
            s.sleep_efficiency, s.sleep_performance,
            st.day_strain, st.calories_active,
            ds.meals_logged, ds.water_ml, ds.calories_consumed, ds.protein_g,
            rem.reminders_due, rem.reminders_completed
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
        RETURN QUERY SELECT 'error'::TEXT, 0, 1;
    END;
END;
$$ LANGUAGE plpgsql;

-- 4. Update dashboard.get_payload to include reminder_summary
-- We need to recreate the function with the new key added
CREATE OR REPLACE FUNCTION dashboard.get_payload(
    for_date DATE DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    target_date DATE := COALESCE(for_date, life.dubai_today());
    payload JSONB;
    facts_computed TIMESTAMPTZ;
    source_latest TIMESTAMPTZ;
    is_today BOOLEAN;
BEGIN
    is_today := (target_date = life.dubai_today());

    IF NOT EXISTS (SELECT 1 FROM life.daily_facts WHERE day = target_date) THEN
        PERFORM life.refresh_daily_facts(target_date);
    ELSE
        SELECT computed_at INTO facts_computed
        FROM life.daily_facts WHERE day = target_date;

        SELECT GREATEST(
            (SELECT MAX(created_at) FROM health.whoop_recovery
             WHERE CASE WHEN is_today THEN date <= target_date ELSE date = target_date END),
            (SELECT MAX(created_at) FROM health.whoop_sleep
             WHERE CASE WHEN is_today THEN date <= target_date ELSE date = target_date END),
            (SELECT MAX(created_at) FROM health.whoop_strain
             WHERE CASE WHEN is_today THEN date <= target_date ELSE date = target_date END),
            (SELECT MAX(recorded_at) FROM health.metrics
             WHERE metric_type = 'weight'
               AND (recorded_at AT TIME ZONE 'Asia/Dubai')::date = target_date),
            (SELECT MAX(created_at) FROM finance.transactions
             WHERE (transaction_at AT TIME ZONE 'Asia/Dubai')::date = target_date)
        ) INTO source_latest;

        IF source_latest IS NOT NULL AND (facts_computed IS NULL OR source_latest > facts_computed) THEN
            PERFORM life.refresh_daily_facts(target_date);
        END IF;
    END IF;

    SELECT jsonb_build_object(
        'meta', jsonb_build_object(
            'schema_version', 8,
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
            'ranked_insights', insights.get_ranked_insights(target_date),
            'category_trends', (
                SELECT COALESCE(jsonb_agg(
                    jsonb_build_object(
                        'type', 'category_trend',
                        'category', category,
                        'change_pct', ROUND(velocity_pct::numeric, 1),
                        'direction', CASE WHEN velocity_pct > 0 THEN 'up' ELSE 'down' END,
                        'detail', category || ' spending ' ||
                            CASE WHEN velocity_pct > 0 THEN 'up' ELSE 'down' END ||
                            ' ' || ROUND(ABS(velocity_pct)::numeric, 0) || '% vs prior period'
                    )
                ), '[]'::jsonb)
                FROM (
                    SELECT category, velocity_pct, trend
                    FROM finance.mv_category_velocity
                    WHERE ABS(velocity_pct) > 25
                      AND trend <> 'insufficient_data'
                    ORDER BY ABS(velocity_pct) DESC
                    LIMIT 3
                ) top_cats
            )
        ),
        'data_pipeline', jsonb_build_object(
            'health', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'feed', feed,
                        'status', COALESCE(status, 'unknown'),
                        'last_sync', to_char(last_sync AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                        'hours_since_sync', ROUND(hours_since_sync::numeric, 1),
                        'stale_feeds', CASE
                            WHEN status IN ('stale', 'critical') THEN jsonb_build_array(feed)
                            ELSE '[]'::jsonb
                        END
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
        ),
        'github_activity', COALESCE(life.get_github_activity_widget(14), '{}'::jsonb),
        'calendar_summary', COALESCE(
            (SELECT jsonb_build_object(
                'meeting_count', cs.meeting_count,
                'meeting_hours', cs.meeting_hours,
                'first_meeting', to_char(cs.first_meeting, 'HH24:MI'),
                'last_meeting', to_char(cs.last_meeting, 'HH24:MI')
            )
            FROM life.v_daily_calendar_summary cs
            WHERE cs.day = target_date),
            '{"meeting_count": 0, "meeting_hours": 0, "first_meeting": null, "last_meeting": null}'::jsonb
        ),
        'reminder_summary', jsonb_build_object(
            'due_today', COALESCE((
                SELECT COUNT(*)
                FROM raw.reminders
                WHERE due_date IS NOT NULL
                  AND (due_date AT TIME ZONE 'Asia/Dubai')::date = target_date
            ), 0),
            'completed_today', COALESCE((
                SELECT COUNT(*)
                FROM raw.reminders
                WHERE is_completed = true
                  AND completed_date IS NOT NULL
                  AND (completed_date AT TIME ZONE 'Asia/Dubai')::date = target_date
            ), 0),
            'overdue_count', COALESCE((
                SELECT COUNT(*)
                FROM raw.reminders
                WHERE due_date IS NOT NULL
                  AND (due_date AT TIME ZONE 'Asia/Dubai')::date < target_date
                  AND (is_completed = false OR is_completed IS NULL)
            ), 0)
        )
    ) INTO payload;

    RETURN payload;
END;
$$ LANGUAGE plpgsql;

COMMIT;
