-- Migration 184: Work hour tracking via geofence system
-- Derives work sessions from core.location_events WHERE category = 'work'
-- Adds work_summary to dashboard payload (schema v19)
-- Adds work observations to explain_today briefing

BEGIN;

-- 1. View: derive work sessions from location enter/exit events
CREATE OR REPLACE VIEW life.v_work_sessions AS
SELECT
    enter_ev.id,
    enter_ev.location_id,
    kl.name AS location_name,
    enter_ev.timestamp AS clock_in,
    exit_ev.timestamp AS clock_out,
    exit_ev.duration_minutes,
    (enter_ev.timestamp AT TIME ZONE 'Asia/Dubai')::date AS work_date
FROM core.location_events enter_ev
JOIN core.known_locations kl
    ON kl.id = enter_ev.location_id
    AND kl.category = 'work'
    AND kl.is_active = true
LEFT JOIN LATERAL (
    SELECT le2.timestamp, le2.duration_minutes
    FROM core.location_events le2
    WHERE le2.location_id = enter_ev.location_id
      AND le2.event_type = 'exit'
      AND le2.timestamp > enter_ev.timestamp
    ORDER BY le2.timestamp ASC
    LIMIT 1
) exit_ev ON TRUE
WHERE enter_ev.event_type = 'enter';

-- 2. Function: get work summary for a given date
CREATE OR REPLACE FUNCTION life.get_work_summary(for_date DATE DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    the_date DATE;
    total_mins INT := 0;
    session_count INT := 0;
    first_in TIMESTAMPTZ;
    last_out TIMESTAMPTZ;
    current_start TIMESTAMPTZ;
    current_elapsed INT;
BEGIN
    the_date := COALESCE(for_date, life.dubai_today());

    -- Completed sessions
    SELECT
        COALESCE(SUM(duration_minutes), 0),
        COUNT(*),
        MIN(clock_in),
        MAX(clock_out)
    INTO total_mins, session_count, first_in, last_out
    FROM life.v_work_sessions
    WHERE work_date = the_date
      AND clock_out IS NOT NULL;

    -- Check for open session (currently at work)
    SELECT le.timestamp INTO current_start
    FROM core.location_events le
    JOIN core.known_locations kl
        ON kl.id = le.location_id
        AND kl.category = 'work'
    WHERE le.event_type = 'enter'
      AND (le.timestamp AT TIME ZONE 'Asia/Dubai')::date = the_date
      AND NOT EXISTS (
          SELECT 1 FROM core.location_events le2
          WHERE le2.location_id = le.location_id
            AND le2.event_type = 'exit'
            AND le2.timestamp > le.timestamp
      )
    ORDER BY le.timestamp DESC
    LIMIT 1;

    IF current_start IS NOT NULL THEN
        current_elapsed := EXTRACT(EPOCH FROM (NOW() - current_start))::INT / 60;
        total_mins := total_mins + current_elapsed;
        session_count := session_count + 1;
        IF first_in IS NULL THEN first_in := current_start; END IF;
    END IF;

    -- Return null if no work activity
    IF total_mins = 0 AND current_start IS NULL THEN
        RETURN NULL;
    END IF;

    RETURN jsonb_build_object(
        'work_date', the_date,
        'total_minutes', total_mins,
        'total_hours', ROUND(total_mins / 60.0, 1),
        'sessions', session_count,
        'first_arrival', first_in,
        'last_departure', last_out,
        'is_at_work', current_start IS NOT NULL,
        'current_session_start', current_start
    );
END;
$$;

-- 3. Update dashboard.get_payload() — schema v19: Added work_summary
CREATE OR REPLACE FUNCTION dashboard.get_payload(for_date date DEFAULT NULL::date)
RETURNS JSONB
LANGUAGE plpgsql STABLE
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
    work_data JSONB;
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

    -- Work summary
    SELECT life.get_work_summary(the_date) INTO work_data;

    -- Build final result (schema_version 19: Added work_summary)
    result := jsonb_build_object(
        'schema_version', 19, 'generated_at', NOW(), 'target_date', the_date,
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
        'bjj_summary', bjj_data,
        'work_summary', work_data
    );

    RETURN result;
END;
$function$;

COMMENT ON FUNCTION dashboard.get_payload IS 'Dashboard payload v19: Added work_summary (hours, sessions, at-work status)';

-- 4. Update life.explain_today() — add work observations
CREATE OR REPLACE FUNCTION life.explain_today(target_date date DEFAULT NULL::date)
RETURNS JSONB
LANGUAGE plpgsql STABLE
AS $function$
DECLARE
    the_day DATE;
    facts RECORD;
    result JSONB;

    -- Structured section summaries (for detail views)
    health_parts TEXT[] := '{}';
    finance_parts TEXT[] := '{}';
    nutrition_parts TEXT[] := '{}';
    activity_parts TEXT[] := '{}';
    data_gaps TEXT[] := '{}';

    -- Priority-ranked observations stored as jsonb array of {p: int, t: text}
    obs JSONB := '[]'::jsonb;

    -- 7-day trends
    recovery_avg_7d NUMERIC;
    recovery_vs_7d NUMERIC;
    sleep_avg_7d NUMERIC;
    sleep_vs_7d NUMERIC;
    spend_avg_7d NUMERIC;
    calories_avg_7d NUMERIC;

    -- BJJ context
    bjj_last_date DATE;
    days_since_bjj INT;
    bjj_streak INT := 0;
    bjj_sessions_week INT := 0;
    day_of_week INT;

    -- Work context
    work_data JSONB;
    work_minutes INT;

    -- Labels
    recovery_label TEXT;
    sleep_label TEXT;
    spend_label TEXT;

    -- Assertions
    assertions JSONB;
    dubai_check BOOLEAN;
    freshness_check BOOLEAN;
    completeness_check BOOLEAN;

    -- Briefing assembly
    final_observations TEXT[];
    max_priority INT;
    briefing TEXT;
BEGIN
    the_day := COALESCE(target_date, life.dubai_today());

    -- ======================================================================
    -- ASSERTIONS (unchanged from v1)
    -- ======================================================================
    dubai_check := life.assert_dubai_day(the_day);
    SELECT * INTO facts FROM life.daily_facts WHERE day = the_day;

    IF facts.computed_at IS NOT NULL THEN
        freshness_check := (NOW() - facts.computed_at) < INTERVAL '6 hours';
    ELSE
        freshness_check := FALSE;
    END IF;
    completeness_check := COALESCE(facts.data_completeness, 0) >= 0.30;

    assertions := jsonb_build_object(
        'dubai_day_valid', dubai_check,
        'data_fresh', freshness_check,
        'data_sufficient', completeness_check,
        'all_passed', dubai_check AND freshness_check AND completeness_check,
        'checked_at', NOW(),
        'target_date', the_day,
        'computed_at', facts.computed_at,
        'data_completeness', facts.data_completeness
    );

    IF facts.day IS NULL THEN
        RETURN jsonb_build_object(
            'target_date', the_day,
            'has_data', FALSE,
            'briefing', 'No data recorded for ' || to_char(the_day, 'FMMonth DD') || '.',
            'data_gaps', ARRAY['No daily_facts row exists for this date'],
            'assertions', assertions
        );
    END IF;

    -- ======================================================================
    -- 7-DAY BASELINES (single query)
    -- ======================================================================
    SELECT
        AVG(recovery_score),
        AVG(sleep_hours),
        AVG(spend_total),
        AVG(calories_consumed)
    INTO recovery_avg_7d, sleep_avg_7d, spend_avg_7d, calories_avg_7d
    FROM life.daily_facts
    WHERE day BETWEEN the_day - 7 AND the_day - 1;

    IF recovery_avg_7d > 0 AND facts.recovery_score IS NOT NULL THEN
        recovery_vs_7d := ROUND(((facts.recovery_score - recovery_avg_7d) / recovery_avg_7d * 100)::numeric, 0);
    END IF;

    IF sleep_avg_7d > 0 AND facts.sleep_hours IS NOT NULL THEN
        sleep_vs_7d := ROUND(((facts.sleep_hours - sleep_avg_7d) / sleep_avg_7d * 100)::numeric, 0);
    END IF;

    -- ======================================================================
    -- BJJ CONTEXT (two lightweight queries)
    -- ======================================================================
    day_of_week := EXTRACT(ISODOW FROM the_day)::INT; -- 1=Mon 7=Sun

    SELECT session_date INTO bjj_last_date
    FROM health.bjj_sessions ORDER BY session_date DESC LIMIT 1;

    IF bjj_last_date IS NOT NULL THEN
        days_since_bjj := the_day - bjj_last_date;
    END IF;

    BEGIN
        SELECT current_streak, sessions_this_week
        INTO bjj_streak, bjj_sessions_week
        FROM health.get_bjj_streaks();
    EXCEPTION WHEN OTHERS THEN
        bjj_streak := 0; bjj_sessions_week := 0;
    END;

    -- ======================================================================
    -- WORK CONTEXT
    -- ======================================================================
    SELECT life.get_work_summary(the_day) INTO work_data;
    IF work_data IS NOT NULL THEN
        work_minutes := (work_data->>'total_minutes')::INT;
    ELSE
        work_minutes := 0;
    END IF;

    -- ======================================================================
    -- SCORE & COLLECT OBSERVATIONS
    -- Priority: 9 = urgent, 7-8 = high, 5-6 = medium, 1-4 = low/positive
    -- ======================================================================

    -- ── RECOVERY ──────────────────────────────────────────────────────────
    IF facts.recovery_score IS NOT NULL THEN
        IF facts.recovery_score < 34 THEN
            recovery_label := 'low';
            -- Combine with deep sleep if also bad
            IF facts.deep_sleep_minutes IS NOT NULL AND facts.deep_sleep_minutes < 45 THEN
                obs := obs || jsonb_build_object('p', 9, 't',
                    'Recovery at ' || facts.recovery_score || '%, deep sleep was only ' ||
                    facts.deep_sleep_minutes || ' min — take it easy today.');
            ELSE
                obs := obs || jsonb_build_object('p', 9, 't',
                    'Recovery is low at ' || facts.recovery_score || '% — prioritize rest.');
            END IF;
        ELSIF recovery_vs_7d IS NOT NULL AND recovery_vs_7d < -10 THEN
            recovery_label := CASE WHEN facts.recovery_score >= 67 THEN 'high' ELSE 'moderate' END;
            -- Combine with deep sleep context if available
            IF facts.deep_sleep_minutes IS NOT NULL AND facts.deep_sleep_minutes < 45 THEN
                obs := obs || jsonb_build_object('p', 8, 't',
                    'Recovery at ' || facts.recovery_score || '%, down ' ||
                    ABS(recovery_vs_7d)::INT::TEXT || '% from your 7-day average — deep sleep was only ' ||
                    facts.deep_sleep_minutes || ' min.');
            ELSE
                obs := obs || jsonb_build_object('p', 7, 't',
                    'Recovery at ' || facts.recovery_score || '%, down ' ||
                    ABS(recovery_vs_7d)::INT::TEXT || '% from your 7-day average.');
            END IF;
        ELSIF facts.recovery_score >= 67 THEN
            recovery_label := 'high';
            obs := obs || jsonb_build_object('p', 3, 't',
                'Recovery is strong at ' || facts.recovery_score || '%.');
        ELSE
            recovery_label := 'moderate';
            -- Moderate + no trend issue = skip briefing
        END IF;
        health_parts := array_append(health_parts,
            'Recovery: ' || facts.recovery_score || '% (' || recovery_label || ')');
    ELSE
        data_gaps := array_append(data_gaps, 'Recovery score not available');
    END IF;

    -- ── SLEEP ─────────────────────────────────────────────────────────────
    IF facts.sleep_hours IS NOT NULL THEN
        IF facts.sleep_hours < 6 THEN
            sleep_label := 'poor';
            obs := obs || jsonb_build_object('p', 8, 't',
                'Only ' || ROUND(facts.sleep_hours, 1) || 'h sleep — you''ll feel it.');
        ELSIF facts.deep_sleep_minutes IS NOT NULL AND facts.deep_sleep_minutes < 45
              -- Don't double-report if already combined with recovery above
              AND (facts.recovery_score IS NULL OR facts.recovery_score >= 34) THEN
            sleep_label := 'poor quality';
            obs := obs || jsonb_build_object('p', 7, 't',
                'Sleep quality was poor — only ' || facts.deep_sleep_minutes || ' min deep sleep.');
        ELSIF facts.sleep_efficiency IS NOT NULL AND facts.sleep_efficiency < 0.80 THEN
            sleep_label := 'poor quality';
            obs := obs || jsonb_build_object('p', 7, 't',
                'Sleep efficiency low at ' || ROUND(facts.sleep_efficiency * 100)::TEXT || '%.');
        ELSIF sleep_vs_7d IS NOT NULL AND sleep_vs_7d < -10 THEN
            sleep_label := 'declining';
            obs := obs || jsonb_build_object('p', 6, 't',
                'Sleep trending down — ' || ROUND(facts.sleep_hours, 1) || 'h vs ' ||
                ROUND(sleep_avg_7d, 1) || 'h average.');
        ELSIF facts.sleep_hours >= 7.5 THEN
            sleep_label := 'good';
            obs := obs || jsonb_build_object('p', 2, 't',
                ROUND(facts.sleep_hours, 1) || 'h of solid sleep.');
        ELSE
            sleep_label := 'fair';
        END IF;
        health_parts := array_append(health_parts,
            'Sleep: ' || ROUND(facts.sleep_hours, 1) || 'h (' || sleep_label || ')');
        IF facts.deep_sleep_minutes IS NOT NULL THEN
            health_parts := array_append(health_parts, 'Deep sleep: ' || facts.deep_sleep_minutes || ' min');
        END IF;
        IF facts.rem_sleep_minutes IS NOT NULL THEN
            health_parts := array_append(health_parts, 'REM sleep: ' || facts.rem_sleep_minutes || ' min');
        END IF;
    ELSE
        data_gaps := array_append(data_gaps, 'Sleep data not available');
    END IF;

    -- ── SPEND ─────────────────────────────────────────────────────────────
    IF facts.spend_total IS NOT NULL AND facts.spend_total > 0 THEN
        IF spend_avg_7d IS NOT NULL AND spend_avg_7d > 0
           AND facts.spend_total > spend_avg_7d * 1.5 THEN
            spend_label := 'unusual';
            IF facts.spend_groceries > facts.spend_total * 0.5 THEN
                obs := obs || jsonb_build_object('p', 8, 't',
                    'Unusual spending: ' || ROUND(facts.spend_total)::TEXT ||
                    ' AED vs your ' || ROUND(spend_avg_7d)::TEXT ||
                    ' average — groceries drove most of it.');
            ELSIF facts.spend_restaurants > facts.spend_total * 0.5 THEN
                obs := obs || jsonb_build_object('p', 8, 't',
                    'Unusual spending: ' || ROUND(facts.spend_total)::TEXT ||
                    ' AED vs your ' || ROUND(spend_avg_7d)::TEXT ||
                    ' average — dining out was the main driver.');
            ELSE
                obs := obs || jsonb_build_object('p', 8, 't',
                    'Unusual spending: ' || ROUND(facts.spend_total)::TEXT ||
                    ' AED vs your ' || ROUND(spend_avg_7d)::TEXT || ' average.');
            END IF;
        ELSIF facts.spend_total >= 500 THEN
            spend_label := 'high';
            obs := obs || jsonb_build_object('p', 5, 't',
                'Heavy spend day: ' || ROUND(facts.spend_total)::TEXT || ' AED.');
        ELSE
            spend_label := 'normal';
        END IF;
        finance_parts := array_append(finance_parts,
            'Spend: ' || ROUND(facts.spend_total)::TEXT || ' AED (' || COALESCE(spend_label, 'normal') || ')');
    END IF;

    -- ── WORK ──────────────────────────────────────────────────────────────
    IF work_minutes > 0 THEN
        IF (work_data->>'is_at_work')::boolean THEN
            IF work_minutes >= 540 THEN
                obs := obs || jsonb_build_object('p', 7, 't',
                    'Long day — ' || ROUND(work_minutes / 60.0, 1) || 'h at work and still going.');
            ELSIF work_minutes >= 480 THEN
                obs := obs || jsonb_build_object('p', 5, 't',
                    'Full day at work — ' || ROUND(work_minutes / 60.0, 1) || 'h and counting.');
            ELSE
                obs := obs || jsonb_build_object('p', 3, 't',
                    'At work — ' || ROUND(work_minutes / 60.0, 1) || 'h so far.');
            END IF;
        ELSE
            IF work_minutes >= 540 THEN
                obs := obs || jsonb_build_object('p', 6, 't',
                    'Long work day — ' || ROUND(work_minutes / 60.0, 1) || 'h today.');
            ELSIF work_minutes >= 480 THEN
                obs := obs || jsonb_build_object('p', 4, 't',
                    ROUND(work_minutes / 60.0, 1) || 'h at work today.');
            END IF;
        END IF;
        activity_parts := array_append(activity_parts,
            ROUND(work_minutes / 60.0, 1) || 'h at work');
    END IF;

    -- ── BJJ ───────────────────────────────────────────────────────────────
    IF days_since_bjj IS NOT NULL AND days_since_bjj = 0 THEN
        obs := obs || jsonb_build_object('p', 4, 't', 'BJJ session logged today — nice work.');
    ELSIF days_since_bjj IS NOT NULL AND days_since_bjj = 1 THEN
        IF facts.recovery_score IS NOT NULL THEN
            IF facts.recovery_score >= 67 THEN
                obs := obs || jsonb_build_object('p', 6, 't',
                    'BJJ yesterday' ||
                    CASE WHEN bjj_streak > 1 THEN ', ' || bjj_streak || '-week streak'
                    ELSE '' END ||
                    '. Recovery at ' || facts.recovery_score || '% — good to go again.');
            ELSIF facts.recovery_score >= 34 THEN
                obs := obs || jsonb_build_object('p', 6, 't',
                    'BJJ yesterday — recovery at ' || facts.recovery_score ||
                    '% is moderate, listen to your body.');
            ELSE
                obs := obs || jsonb_build_object('p', 8, 't',
                    'BJJ yesterday and recovery is low (' || facts.recovery_score ||
                    '%) — consider a rest day.');
            END IF;
        ELSE
            obs := obs || jsonb_build_object('p', 4, 't', 'Trained BJJ yesterday.');
        END IF;
    ELSIF bjj_streak > 1 AND days_since_bjj IS NOT NULL AND days_since_bjj <= 3 THEN
        obs := obs || jsonb_build_object('p', 3, 't',
            bjj_streak || '-week training streak going.');
    END IF;

    -- Nudge: no training this week, Thursday or later
    IF bjj_sessions_week = 0 AND day_of_week >= 4 THEN
        obs := obs || jsonb_build_object('p', 6, 't',
            'No training yet this week — ' ||
            CASE day_of_week
                WHEN 4 THEN 'Thursday already.'
                WHEN 5 THEN 'Friday already.'
                WHEN 6 THEN 'Saturday, last chance.'
                WHEN 7 THEN 'week''s almost over.'
            END);
    END IF;

    -- ── NUTRITION ─────────────────────────────────────────────────────────
    IF facts.protein_g IS NOT NULL AND facts.protein_g < 120 AND facts.meals_logged > 0 THEN
        obs := obs || jsonb_build_object('p', 6, 't',
            'Protein low at ' || facts.protein_g || 'g, aim for 120+.');
    END IF;

    IF facts.calories_consumed IS NOT NULL AND calories_avg_7d IS NOT NULL AND calories_avg_7d > 0 THEN
        IF facts.calories_consumed < calories_avg_7d * 0.6 AND facts.meals_logged > 0 THEN
            obs := obs || jsonb_build_object('p', 6, 't',
                'Calories are low at ' || facts.calories_consumed || ' kcal.');
        ELSIF facts.calories_consumed > calories_avg_7d * 1.4 THEN
            obs := obs || jsonb_build_object('p', 5, 't',
                'High calorie day: ' || facts.calories_consumed || ' kcal vs ' ||
                ROUND(calories_avg_7d)::TEXT || ' avg.');
        END IF;
    END IF;

    -- ── MOOD / ENERGY ─────────────────────────────────────────────────────
    IF facts.avg_mood IS NOT NULL AND facts.avg_mood < 5 THEN
        obs := obs || jsonb_build_object('p', 6, 't',
            'Mood is on the lower side (' || ROUND(facts.avg_mood, 1) || '/10).');
    END IF;
    IF facts.avg_energy IS NOT NULL AND facts.avg_energy < 5 THEN
        obs := obs || jsonb_build_object('p', 6, 't',
            'Energy is low (' || ROUND(facts.avg_energy, 1) || '/10) — pace yourself.');
    END IF;

    -- ======================================================================
    -- ASSEMBLE BRIEFING: top 5 observations sorted by priority
    -- ======================================================================
    SELECT array_agg(t ORDER BY p DESC), MAX(p)
    INTO final_observations, max_priority
    FROM (
        SELECT elem->>'t' AS t, (elem->>'p')::int AS p
        FROM jsonb_array_elements(obs) elem
        ORDER BY (elem->>'p')::int DESC
        LIMIT 5
    ) top;

    IF final_observations IS NULL OR array_length(final_observations, 1) IS NULL THEN
        briefing := 'Solid day across the board — recovery, sleep, and spending all tracking normally.';
    ELSIF max_priority <= 3 THEN
        briefing := 'Solid day across the board. ' || array_to_string(final_observations, ' ');
    ELSE
        briefing := array_to_string(final_observations, ' ');
    END IF;

    -- ======================================================================
    -- STRUCTURED SECTIONS (detail views — always populated)
    -- ======================================================================
    IF facts.hrv IS NOT NULL THEN
        health_parts := array_append(health_parts, 'HRV: ' || ROUND(facts.hrv)::TEXT || 'ms');
    END IF;
    IF facts.strain IS NOT NULL THEN
        health_parts := array_append(health_parts, 'Strain: ' || ROUND(facts.strain, 1)::TEXT);
    END IF;
    IF facts.weight_kg IS NOT NULL THEN
        health_parts := array_append(health_parts, 'Weight: ' || ROUND(facts.weight_kg, 1)::TEXT || 'kg');
    ELSE
        data_gaps := array_append(data_gaps, 'No weight recorded');
    END IF;

    IF facts.spend_groceries > 0 THEN
        finance_parts := array_append(finance_parts, 'Groceries: ' || ROUND(facts.spend_groceries)::TEXT || ' AED');
    END IF;
    IF facts.spend_restaurants > 0 THEN
        finance_parts := array_append(finance_parts, 'Dining: ' || ROUND(facts.spend_restaurants)::TEXT || ' AED');
    END IF;
    IF facts.spend_transport > 0 THEN
        finance_parts := array_append(finance_parts, 'Transport: ' || ROUND(facts.spend_transport)::TEXT || ' AED');
    END IF;
    IF facts.income_total > 0 THEN
        finance_parts := array_append(finance_parts, 'Income: ' || ROUND(facts.income_total)::TEXT || ' AED');
    END IF;

    IF facts.meals_logged > 0 THEN
        nutrition_parts := array_append(nutrition_parts, facts.meals_logged || ' meal(s)');
        IF facts.calories_consumed IS NOT NULL THEN
            nutrition_parts := array_append(nutrition_parts, facts.calories_consumed || ' kcal');
        END IF;
        IF facts.protein_g IS NOT NULL THEN
            nutrition_parts := array_append(nutrition_parts, facts.protein_g || 'g protein');
        END IF;
    ELSE
        data_gaps := array_append(data_gaps, 'No nutrition data logged');
    END IF;
    IF facts.water_ml > 0 THEN
        nutrition_parts := array_append(nutrition_parts, ROUND(facts.water_ml / 1000.0, 1) || 'L water');
    END IF;

    IF facts.listening_minutes IS NOT NULL AND facts.listening_minutes > 0 THEN
        activity_parts := array_append(activity_parts, life.format_duration(facts.listening_minutes) || ' music');
    END IF;
    IF facts.fasting_hours IS NOT NULL AND facts.fasting_hours > 0 THEN
        activity_parts := array_append(activity_parts, ROUND(facts.fasting_hours, 1) || 'h fasted');
    END IF;
    IF facts.reminders_completed > 0 THEN
        activity_parts := array_append(activity_parts, facts.reminders_completed || ' reminder(s) done');
    END IF;

    -- ======================================================================
    -- RETURN (same shape as v1, with work_minutes added to activity)
    -- ======================================================================
    result := jsonb_build_object(
        'target_date', the_day,
        'has_data', TRUE,
        'health', jsonb_build_object(
            'recovery_label', recovery_label,
            'sleep_label', sleep_label,
            'recovery_score', facts.recovery_score,
            'sleep_hours', facts.sleep_hours,
            'hrv', facts.hrv,
            'strain', facts.strain,
            'weight_kg', facts.weight_kg,
            'summary', health_parts
        ),
        'finance', jsonb_build_object(
            'spend_label', spend_label,
            'spend_total', facts.spend_total,
            'transaction_count', facts.transaction_count,
            'summary', finance_parts
        ),
        'nutrition', jsonb_build_object(
            'meals_logged', facts.meals_logged,
            'calories', facts.calories_consumed,
            'protein_g', facts.protein_g,
            'water_ml', facts.water_ml,
            'summary', nutrition_parts
        ),
        'activity', jsonb_build_object(
            'listening_minutes', facts.listening_minutes,
            'fasting_hours', facts.fasting_hours,
            'reminders_due', facts.reminders_due,
            'reminders_completed', facts.reminders_completed,
            'work_minutes', work_minutes,
            'summary', activity_parts
        ),
        'briefing', briefing,
        'data_gaps', data_gaps,
        'data_completeness', facts.data_completeness,
        'computed_at', facts.computed_at,
        'assertions', assertions
    );

    RETURN result;
END;
$function$;

-- 5. Seed work location (UPDATE WITH YOUR COORDINATES)
-- Uncomment and set lat/lng when ready:
-- INSERT INTO core.known_locations (name, category, lat, lng, radius_meters)
-- VALUES ('work', 'work', <YOUR_LAT>, <YOUR_LNG>, 200)
-- ON CONFLICT (name) DO NOTHING;

INSERT INTO ops.schema_migrations (filename)
VALUES ('184_work_hour_tracking.up.sql');

COMMIT;
