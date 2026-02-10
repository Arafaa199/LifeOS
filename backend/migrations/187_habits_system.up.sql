BEGIN;

-- ============================================================================
-- Migration 187: Habits System
-- Creates habit tracking tables, streak functions, seeds starter habits,
-- updates dashboard.get_payload() to v21 with habits_today
-- ============================================================================

-- 1. Create life.habits table
CREATE TABLE IF NOT EXISTS life.habits (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    category TEXT CHECK (category IN ('health', 'fitness', 'productivity', 'mindfulness')),
    frequency TEXT NOT NULL DEFAULT 'daily',
    target_count INT NOT NULL DEFAULT 1,
    icon TEXT,
    color TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Create life.habit_completions table
CREATE TABLE IF NOT EXISTS life.habit_completions (
    id SERIAL PRIMARY KEY,
    habit_id INT NOT NULL REFERENCES life.habits(id),
    completed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    count INT NOT NULL DEFAULT 1,
    notes TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_habit_completions_unique_day
    ON life.habit_completions (habit_id, ((completed_at AT TIME ZONE 'Asia/Dubai')::date));

CREATE INDEX IF NOT EXISTS idx_habit_completions_habit_date
    ON life.habit_completions (habit_id, ((completed_at AT TIME ZONE 'Asia/Dubai')::date) DESC);

-- 3. Create life.get_habit_streaks(p_habit_id)
CREATE OR REPLACE FUNCTION life.get_habit_streaks(p_habit_id INT)
RETURNS TABLE(current_streak INT, longest_streak INT, total_completions BIGINT)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_current INT := 0;
    v_longest INT := 0;
    v_total BIGINT;
    v_check_date DATE;
    v_found BOOLEAN;
BEGIN
    -- Total completions
    SELECT COUNT(*) INTO v_total
    FROM life.habit_completions
    WHERE habit_id = p_habit_id;

    -- Current streak: walk backwards from today
    v_check_date := life.dubai_today();
    LOOP
        SELECT EXISTS(
            SELECT 1 FROM life.habit_completions
            WHERE habit_id = p_habit_id
              AND (completed_at AT TIME ZONE 'Asia/Dubai')::date = v_check_date
        ) INTO v_found;

        EXIT WHEN NOT v_found;
        v_current := v_current + 1;
        v_check_date := v_check_date - 1;
    END LOOP;

    -- Longest streak: scan all completion dates
    v_longest := v_current;
    DECLARE
        v_streak INT := 0;
        v_prev_date DATE := NULL;
        rec RECORD;
    BEGIN
        FOR rec IN
            SELECT DISTINCT (completed_at AT TIME ZONE 'Asia/Dubai')::date AS d
            FROM life.habit_completions
            WHERE habit_id = p_habit_id
            ORDER BY d
        LOOP
            IF v_prev_date IS NULL OR rec.d = v_prev_date + 1 THEN
                v_streak := v_streak + 1;
            ELSE
                v_streak := 1;
            END IF;
            IF v_streak > v_longest THEN
                v_longest := v_streak;
            END IF;
            v_prev_date := rec.d;
        END LOOP;
    END;

    RETURN QUERY SELECT v_current, v_longest, v_total;
END;
$$;

-- 4. Create life.get_habits_today()
CREATE OR REPLACE FUNCTION life.get_habits_today()
RETURNS TABLE(
    id INT,
    name TEXT,
    category TEXT,
    frequency TEXT,
    target_count INT,
    icon TEXT,
    color TEXT,
    is_active BOOLEAN,
    completed_today BOOLEAN,
    completion_count INT,
    current_streak INT,
    longest_streak INT,
    total_completions BIGINT,
    last_7_days BOOLEAN[]
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_today DATE := life.dubai_today();
    rec RECORD;
    v_days BOOLEAN[];
    v_day DATE;
    v_streak RECORD;
BEGIN
    FOR rec IN
        SELECT h.id, h.name, h.category, h.frequency, h.target_count,
               h.icon, h.color, h.is_active
        FROM life.habits h
        WHERE h.is_active = TRUE
        ORDER BY h.category NULLS LAST, h.name
    LOOP
        -- Check today's completion
        SELECT COALESCE(hc.count, 0) INTO completion_count
        FROM life.habit_completions hc
        WHERE hc.habit_id = rec.id
          AND (hc.completed_at AT TIME ZONE 'Asia/Dubai')::date = v_today;

        IF NOT FOUND THEN
            completion_count := 0;
        END IF;

        completed_today := completion_count >= rec.target_count;

        -- Last 7 days
        v_days := ARRAY[]::BOOLEAN[];
        FOR i IN REVERSE 6..0 LOOP
            v_day := v_today - i;
            v_days := array_append(v_days, EXISTS(
                SELECT 1 FROM life.habit_completions hc
                WHERE hc.habit_id = rec.id
                  AND (hc.completed_at AT TIME ZONE 'Asia/Dubai')::date = v_day
            ));
        END LOOP;
        last_7_days := v_days;

        -- Streaks
        SELECT s.current_streak, s.longest_streak, s.total_completions
        INTO v_streak
        FROM life.get_habit_streaks(rec.id) s;

        id := rec.id;
        name := rec.name;
        category := rec.category;
        frequency := rec.frequency;
        target_count := rec.target_count;
        icon := rec.icon;
        color := rec.color;
        is_active := rec.is_active;
        current_streak := v_streak.current_streak;
        longest_streak := v_streak.longest_streak;
        total_completions := v_streak.total_completions;

        RETURN NEXT;
    END LOOP;
END;
$$;

-- 5. Seed 5 starter habits
INSERT INTO life.habits (name, category, target_count, icon, color) VALUES
    ('Water', 'health', 8, 'drop.fill', '#4FC3F7'),
    ('BJJ Training', 'fitness', 1, 'figure.martial.arts', '#FF7043'),
    ('Supplements', 'health', 1, 'leaf.fill', '#66BB6A'),
    ('Weight Log', 'health', 1, 'scalemass', '#AB47BC'),
    ('Meal Log', 'health', 1, 'fork.knife', '#FFA726')
ON CONFLICT DO NOTHING;

-- 6. Update dashboard.get_payload() to v21 with habits_today
CREATE OR REPLACE FUNCTION dashboard.get_payload(for_date DATE DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql STABLE AS $$
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
    weekly_review_data JSONB;
    habits_data JSONB;
BEGIN
    the_date := COALESCE(for_date, life.dubai_today());
    SELECT * INTO facts_row FROM life.daily_facts WHERE day = the_date;

    -- Get latest known weight as fallback
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

    -- Fasting
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

    -- Music
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

    -- Mood
    SELECT COALESCE(
        (SELECT jsonb_build_object(
            'mood_score', mood_score,
            'energy_score', energy_score,
            'logged_at', logged_at,
            'notes', notes
        ) FROM raw.v_daily_mood_summary WHERE day = the_date),
        NULL
    ) INTO mood_data;

    -- BJJ
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

    -- Weekly review (latest with score)
    BEGIN
        SELECT jsonb_build_object(
            'week_start', wr.week_start,
            'week_end', wr.week_end,
            'score', wr.score,
            'summary_text', wr.summary_text,
            'avg_recovery', wr.avg_recovery,
            'avg_sleep_hours', wr.avg_sleep_hours,
            'bjj_sessions', wr.bjj_sessions,
            'total_spent', wr.total_spent,
            'habit_completion_pct', wr.habit_completion_pct,
            'spending_trend', wr.spending_trend,
            'recovery_trend', wr.recovery_trend,
            'generated_at', wr.generated_at
        ) INTO weekly_review_data
        FROM insights.weekly_reports wr
        WHERE wr.score IS NOT NULL
        ORDER BY wr.week_start DESC
        LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
        weekly_review_data := NULL;
    END;

    -- Habits today
    BEGIN
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', h.id,
            'name', h.name,
            'category', h.category,
            'frequency', h.frequency,
            'target_count', h.target_count,
            'icon', h.icon,
            'color', h.color,
            'completed_today', h.completed_today,
            'completion_count', h.completion_count,
            'current_streak', h.current_streak,
            'longest_streak', h.longest_streak,
            'total_completions', h.total_completions,
            'last_7_days', h.last_7_days
        ) ORDER BY h.category NULLS LAST, h.name), '[]'::jsonb)
        INTO habits_data
        FROM life.get_habits_today() h;
    EXCEPTION WHEN OTHERS THEN
        habits_data := '[]'::jsonb;
    END;

    -- Build final result (schema_version 21: Added habits_today)
    result := jsonb_build_object(
        'schema_version', 21, 'generated_at', NOW(), 'target_date', the_date,
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
        'work_summary', work_data,
        'latest_weekly_review', weekly_review_data,
        'habits_today', habits_data
    );

    RETURN result;
END;
$$;

INSERT INTO ops.schema_migrations (filename) VALUES ('187_habits_system.up.sql');

COMMIT;
