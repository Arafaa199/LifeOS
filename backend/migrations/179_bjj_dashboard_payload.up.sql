BEGIN;

-- Migration 179: Add bjj_summary to dashboard.get_payload()
-- Wires health.get_bjj_streaks() into dashboard payload so BJJCardView
-- can render from cached dashboard data without a separate API call.
-- Schema version 17 → 18

CREATE OR REPLACE FUNCTION dashboard.get_payload(for_date date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    the_date DATE;
    result JSONB;
    facts_row RECORD;
    latest_weight NUMERIC(5,2);
    finance_data JSONB;
    feed_data JSONB;
    insights_data JSONB;
    calendar_data JSONB;
    reminder_data JSONB;
    github_data JSONB;
    fasting_data JSONB;
    medications_data JSONB;
    explain_data JSONB;
    streaks_data JSONB;
    music_data JSONB;
    mood_data JSONB;
    bjj_data JSONB;
BEGIN
    the_date := COALESCE(for_date, life.dubai_today());
    SELECT * INTO facts_row FROM life.daily_facts WHERE day = the_date;

    -- Get latest known weight as fallback (from any day with weight data)
    SELECT weight_kg INTO latest_weight
    FROM life.daily_facts
    WHERE weight_kg IS NOT NULL
    ORDER BY day DESC
    LIMIT 1;

    -- Finance summary
    SELECT jsonb_build_object(
        'spend_total', COALESCE(facts_row.spend_total, 0),
        'spend_groceries', COALESCE(facts_row.spend_groceries, 0),
        'spend_restaurants', COALESCE(facts_row.spend_restaurants, 0),
        'spend_transport', COALESCE(facts_row.spend_transport, 0),
        'income_total', COALESCE(facts_row.income_total, 0),
        'transaction_count', COALESCE(facts_row.transaction_count, 0)
    ) INTO finance_data;

    -- Feed status
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'feed', source, 'status', status, 'lastSync', last_event_at,
            'hoursSinceSync', EXTRACT(EPOCH FROM (NOW() - last_event_at)) / 3600
        )
    ), '[]'::jsonb) INTO feed_data FROM life.feed_status;

    -- Insights
    SELECT COALESCE(insights.get_ranked_insights(the_date), '{}'::jsonb) INTO insights_data;

    -- Calendar
    SELECT COALESCE(
        (SELECT jsonb_build_object(
            'meeting_count', meeting_count, 'meeting_hours', meeting_hours,
            'first_meeting', first_meeting, 'last_meeting', last_meeting
        ) FROM life.v_daily_calendar_summary WHERE day = the_date),
        jsonb_build_object('meeting_count', 0, 'meeting_hours', 0, 'first_meeting', NULL, 'last_meeting', NULL)
    ) INTO calendar_data;

    -- Reminders
    SELECT jsonb_build_object(
        'due_today', COALESCE(facts_row.reminders_due, 0),
        'completed_today', COALESCE(facts_row.reminders_completed, 0),
        'overdue_count', (SELECT COUNT(*) FROM raw.reminders WHERE deleted_at IS NULL AND is_completed = false AND due_date < the_date)::int
    ) INTO reminder_data;

    -- GitHub
    SELECT COALESCE(life.get_github_activity_widget(14), '{}'::jsonb) INTO github_data;

    -- Fasting (includes hours_since_meal and last_meal_at)
    SELECT health.get_fasting_status() INTO fasting_data;

    -- Medications summary
    SELECT jsonb_build_object(
        'due_today', COALESCE(SUM(CASE WHEN status IN ('scheduled', 'taken', 'skipped') THEN 1 ELSE 0 END)::int, 0),
        'taken_today', COALESCE(SUM(CASE WHEN status = 'taken' THEN 1 ELSE 0 END)::int, 0),
        'skipped_today', COALESCE(SUM(CASE WHEN status = 'skipped' THEN 1 ELSE 0 END)::int, 0),
        'adherence_pct', CASE
            WHEN COUNT(*) FILTER (WHERE status IN ('taken', 'skipped')) > 0
            THEN ROUND(
                COUNT(*) FILTER (WHERE status = 'taken')::numeric /
                NULLIF(COUNT(*) FILTER (WHERE status IN ('taken', 'skipped')), 0) * 100,
                1
            )
            ELSE NULL
        END,
        'medications', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'name', medication_name,
                'status', status,
                'scheduled_time', scheduled_time::text,
                'taken_at', taken_at
            ) ORDER BY scheduled_time NULLS LAST)
            FROM health.medications
            WHERE scheduled_date = the_date
        ), '[]'::jsonb)
    )
    INTO medications_data
    FROM health.medications
    WHERE scheduled_date = the_date;

    -- Default if no medication data
    IF medications_data IS NULL OR medications_data->>'due_today' IS NULL THEN
        medications_data := jsonb_build_object(
            'due_today', 0,
            'taken_today', 0,
            'skipped_today', 0,
            'adherence_pct', NULL,
            'medications', '[]'::jsonb
        );
    END IF;

    -- Explain Today
    SELECT life.explain_today(the_date) INTO explain_data;

    -- Streaks
    SELECT life.get_streaks() INTO streaks_data;

    -- Music listening summary for today
    SELECT COALESCE(
        (SELECT jsonb_build_object(
            'tracks_played', tracks_played,
            'total_minutes', total_minutes,
            'unique_artists', unique_artists,
            'top_artist', top_artist,
            'top_album', top_album
        ) FROM life.v_daily_music_summary WHERE day = the_date),
        jsonb_build_object('tracks_played', 0, 'total_minutes', 0, 'unique_artists', 0, 'top_artist', NULL, 'top_album', NULL)
    ) INTO music_data;

    -- Mood summary for today (latest entry)
    SELECT COALESCE(
        (SELECT jsonb_build_object(
            'mood_score', mood_score,
            'energy_score', energy_score,
            'logged_at', logged_at,
            'notes', notes
        ) FROM raw.v_daily_mood_summary WHERE day = the_date),
        NULL
    ) INTO mood_data;

    -- BJJ summary (streak + last session date)
    BEGIN
        SELECT jsonb_build_object(
            'current_streak', s.current_streak,
            'longest_streak', s.longest_streak,
            'total_sessions', s.total_sessions,
            'sessions_this_week', s.sessions_this_week,
            'sessions_this_month', s.sessions_this_month,
            'last_session_date', (SELECT MAX(session_date) FROM health.bjj_sessions)
        ) INTO bjj_data
        FROM health.get_bjj_streaks() s;
    EXCEPTION WHEN OTHERS THEN
        bjj_data := NULL;
    END;

    -- Build final result (schema_version 18: Added bjj_summary)
    result := jsonb_build_object(
        'schema_version', 18, 'generated_at', NOW(), 'target_date', the_date,
        'today_facts', jsonb_build_object(
            'day', the_date, 'recovery_score', facts_row.recovery_score, 'hrv', facts_row.hrv,
            'rhr', facts_row.rhr, 'sleep_minutes', facts_row.sleep_minutes,
            'sleep_hours', facts_row.sleep_hours,
            'deep_sleep_minutes', facts_row.deep_sleep_minutes,
            'rem_sleep_minutes', facts_row.rem_sleep_minutes,
            'deep_sleep_hours', facts_row.deep_sleep_hours,
            'sleep_efficiency', facts_row.sleep_efficiency, 'strain', facts_row.strain,
            'weight_kg', COALESCE(facts_row.weight_kg, latest_weight),
            'spend_total', facts_row.spend_total,
            'spend_groceries', COALESCE(facts_row.spend_groceries, 0),
            'spend_restaurants', COALESCE(facts_row.spend_restaurants, 0),
            'income_total', COALESCE(facts_row.income_total, 0),
            'transaction_count', COALESCE(facts_row.transaction_count, 0),
            'spend_vs_7d', ROUND(((facts_row.spend_total - (SELECT AVG(spend_total) FROM life.daily_facts WHERE day BETWEEN the_date - 7 AND the_date - 1)) / NULLIF((SELECT AVG(spend_total) FROM life.daily_facts WHERE day BETWEEN the_date - 7 AND the_date - 1), 0) * 100)::numeric, 1),
            'spend_unusual', facts_row.spend_total > COALESCE((SELECT AVG(spend_total) + 2 * STDDEV(spend_total) FROM life.daily_facts WHERE day BETWEEN the_date - 30 AND the_date - 1), 9999),
            'meals_logged', COALESCE(facts_row.meals_logged, 0), 'water_ml', COALESCE(facts_row.water_ml, 0),
            'calories_consumed', facts_row.calories_consumed, 'protein_g', facts_row.protein_g,
            'data_completeness', facts_row.data_completeness,
            'avg_mood', facts_row.avg_mood,
            'avg_energy', facts_row.avg_energy
        ),
        'finance_summary', finance_data, 'feed_status', feed_data,
        'stale_feeds', (SELECT COALESCE(array_agg(source), '{}') FROM life.feed_status WHERE status IN ('stale', 'error')),
        'daily_insights', insights_data, 'calendar_summary', calendar_data,
        'reminder_summary', reminder_data, 'github_activity', github_data,
        'fasting', fasting_data,
        'medications_today', medications_data,
        'explain_today', explain_data,
        'streaks', streaks_data,
        'music_today', music_data,
        'mood_today', mood_data,
        'bjj_summary', bjj_data
    );

    RETURN result;
END;
$function$;

COMMENT ON FUNCTION dashboard.get_payload IS 'Dashboard payload v18: Added bjj_summary (streak, sessions, last_session_date)';

-- Track migration
INSERT INTO ops.schema_migrations (filename)
VALUES ('179_bjj_dashboard_payload.up.sql')
ON CONFLICT (filename) DO NOTHING;

COMMIT;
