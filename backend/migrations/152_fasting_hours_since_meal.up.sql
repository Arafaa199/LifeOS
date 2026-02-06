-- Migration 152: Add hours_since_meal to fasting status
-- Shows elapsed time since last food_log entry for passive IF tracking
-- Schema version: 12 → 13

-- Rewrite get_fasting_status to include hours_since_meal from nutrition.food_log
CREATE OR REPLACE FUNCTION health.get_fasting_status()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    active_session RECORD;
    elapsed_hours NUMERIC(5,2);
    last_meal_at TIMESTAMPTZ;
    hours_since_meal NUMERIC(5,1);
BEGIN
    -- Check for explicit fasting session
    SELECT id, started_at, ended_at
    INTO active_session
    FROM health.fasting_sessions
    WHERE ended_at IS NULL
    ORDER BY started_at DESC
    LIMIT 1;

    -- Get last meal from food_log
    SELECT MAX(logged_at) INTO last_meal_at FROM nutrition.food_log;

    IF last_meal_at IS NOT NULL THEN
        hours_since_meal := ROUND(EXTRACT(EPOCH FROM (NOW() - last_meal_at)) / 3600, 1);
    ELSE
        hours_since_meal := NULL;
    END IF;

    IF active_session.id IS NULL THEN
        -- No active explicit fast
        RETURN jsonb_build_object(
            'is_active', false,
            'started_at', NULL,
            'elapsed_hours', NULL,
            'session_id', NULL,
            'hours_since_meal', hours_since_meal,
            'last_meal_at', last_meal_at
        );
    ELSE
        elapsed_hours := ROUND(EXTRACT(EPOCH FROM (NOW() - active_session.started_at)) / 3600, 2);
        RETURN jsonb_build_object(
            'is_active', true,
            'session_id', active_session.id,
            'started_at', active_session.started_at,
            'elapsed_hours', elapsed_hours,
            'hours_since_meal', hours_since_meal,
            'last_meal_at', last_meal_at
        );
    END IF;
END;
$function$;

-- Update dashboard.get_payload schema version to 13
-- Note: The function already calls health.get_fasting_status(), so the new fields
-- will automatically flow through. We just need to bump the version.
CREATE OR REPLACE FUNCTION dashboard.get_payload(for_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    the_date DATE;
    result JSONB;
    facts_row RECORD;
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
BEGIN
    the_date := COALESCE(for_date, life.dubai_today());
    SELECT * INTO facts_row FROM life.daily_facts WHERE day = the_date;

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

    -- Fasting (now includes hours_since_meal and last_meal_at)
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

    -- Build final result (schema_version 13: Added hours_since_meal to fasting)
    result := jsonb_build_object(
        'schema_version', 13, 'generated_at', NOW(), 'target_date', the_date,
        'today_facts', jsonb_build_object(
            'day', the_date, 'recovery_score', facts_row.recovery_score, 'hrv', facts_row.hrv,
            'rhr', facts_row.rhr, 'sleep_minutes', facts_row.sleep_minutes,
            'sleep_hours', facts_row.sleep_hours, 'deep_sleep_hours', facts_row.deep_sleep_hours,
            'sleep_efficiency', facts_row.sleep_efficiency, 'strain', facts_row.strain,
            'weight_kg', facts_row.weight_kg, 'spend_total', facts_row.spend_total,
            'spend_vs_7d', ROUND(((facts_row.spend_total - (SELECT AVG(spend_total) FROM life.daily_facts WHERE day BETWEEN the_date - 7 AND the_date - 1)) / NULLIF((SELECT AVG(spend_total) FROM life.daily_facts WHERE day BETWEEN the_date - 7 AND the_date - 1), 0) * 100)::numeric, 1),
            'spend_unusual', facts_row.spend_total > COALESCE((SELECT AVG(spend_total) + 2 * STDDEV(spend_total) FROM life.daily_facts WHERE day BETWEEN the_date - 30 AND the_date - 1), 9999),
            'meals_logged', COALESCE(facts_row.meals_logged, 0), 'water_ml', COALESCE(facts_row.water_ml, 0),
            'calories_consumed', facts_row.calories_consumed, 'protein_g', facts_row.protein_g,
            'data_completeness', facts_row.data_completeness
        ),
        'finance_summary', finance_data, 'feed_status', feed_data,
        'stale_feeds', (SELECT COALESCE(array_agg(source), '{}') FROM life.feed_status WHERE status IN ('stale', 'error')),
        'daily_insights', insights_data, 'calendar_summary', calendar_data,
        'reminder_summary', reminder_data, 'github_activity', github_data,
        'fasting', fasting_data,
        'medications_today', medications_data,
        'explain_today', explain_data,
        'streaks', streaks_data
    );

    RETURN result;
END;
$function$;

-- Log migration
INSERT INTO ops.schema_migrations (filename)
VALUES ('152_fasting_hours_since_meal.up.sql')
ON CONFLICT DO NOTHING;

COMMENT ON FUNCTION health.get_fasting_status() IS 'Returns fasting status with both explicit session and passive hours_since_meal from food_log';
