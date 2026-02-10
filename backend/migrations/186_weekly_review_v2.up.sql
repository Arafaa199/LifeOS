BEGIN;

-- ============================================================================
-- Migration 186: Weekly Review v2
-- Extends insights.weekly_reports with new metrics, rewrites generate function,
-- updates dashboard.get_payload() to v20 with latest_weekly_review
-- ============================================================================

-- 1. Add missing columns to insights.weekly_reports
ALTER TABLE insights.weekly_reports
    ADD COLUMN IF NOT EXISTS score INTEGER,
    ADD COLUMN IF NOT EXISTS bjj_sessions INTEGER,
    ADD COLUMN IF NOT EXISTS bjj_streak INTEGER,
    ADD COLUMN IF NOT EXISTS avg_calories INTEGER,
    ADD COLUMN IF NOT EXISTS avg_protein INTEGER,
    ADD COLUMN IF NOT EXISTS water_days INTEGER,
    ADD COLUMN IF NOT EXISTS fasting_days INTEGER,
    ADD COLUMN IF NOT EXISTS avg_work_hours NUMERIC(4,2),
    ADD COLUMN IF NOT EXISTS habit_completion_pct NUMERIC(5,2),
    ADD COLUMN IF NOT EXISTS summary_text TEXT;

-- 2. Rewrite insights.generate_weekly_report()
CREATE OR REPLACE FUNCTION insights.generate_weekly_report(target_week_start DATE DEFAULT NULL)
RETURNS INTEGER
LANGUAGE plpgsql AS $$
DECLARE
    v_week_start DATE;
    v_week_end DATE;
    -- Health
    v_avg_recovery NUMERIC(5,2);
    v_avg_hrv NUMERIC(6,2);
    v_avg_sleep_hours NUMERIC(4,2);
    v_recovery_trend VARCHAR(20);
    v_prev_recovery NUMERIC(5,2);
    v_days_with_health INTEGER;
    -- Nutrition
    v_avg_calories INTEGER;
    v_avg_protein INTEGER;
    v_water_days INTEGER;
    v_fasting_days INTEGER;
    -- BJJ
    v_bjj_sessions INTEGER;
    v_bjj_streak INTEGER;
    -- Work
    v_avg_work_hours NUMERIC(4,2);
    -- Finance
    v_total_spent NUMERIC(12,2);
    v_total_income NUMERIC(12,2);
    v_top_category VARCHAR(50);
    v_spending_trend VARCHAR(20);
    v_prev_week_spent NUMERIC(12,2);
    -- Productivity
    v_total_commits INTEGER;
    v_active_days INTEGER;
    -- Habits
    v_habit_completion_pct NUMERIC(5,2);
    -- Alerts
    v_budget_alerts INTEGER;
    v_anomaly_count INTEGER;
    v_critical_alerts INTEGER;
    -- Derived
    v_score INTEGER;
    v_summary_text TEXT;
    v_markdown TEXT;
    v_highlights JSONB;
    v_report_id INTEGER;
BEGIN
    -- Default to last complete week (Monday-Sunday)
    IF target_week_start IS NULL THEN
        v_week_start := date_trunc('week', life.dubai_today() - INTERVAL '7 days')::date;
    ELSE
        v_week_start := target_week_start;
    END IF;
    v_week_end := v_week_start + INTERVAL '6 days';

    -- =========================================================================
    -- HEALTH from daily_facts
    -- =========================================================================
    SELECT
        AVG(recovery_score),
        AVG(hrv),
        AVG(sleep_hours),
        COUNT(*) FILTER (WHERE recovery_score IS NOT NULL)
    INTO v_avg_recovery, v_avg_hrv, v_avg_sleep_hours, v_days_with_health
    FROM life.daily_facts
    WHERE day BETWEEN v_week_start AND v_week_end;

    -- Previous week recovery for trend
    SELECT AVG(recovery_score) INTO v_prev_recovery
    FROM life.daily_facts
    WHERE day BETWEEN v_week_start - 7 AND v_week_start - 1;

    v_recovery_trend := CASE
        WHEN v_avg_recovery IS NULL THEN 'no_data'
        WHEN v_prev_recovery IS NULL THEN 'no_data'
        WHEN v_avg_recovery > v_prev_recovery + 5 THEN 'improving'
        WHEN v_avg_recovery < v_prev_recovery - 5 THEN 'declining'
        ELSE 'stable'
    END;

    -- =========================================================================
    -- NUTRITION from daily_facts
    -- =========================================================================
    SELECT
        AVG(calories_consumed)::integer,
        AVG(protein_g)::integer,
        COUNT(*) FILTER (WHERE COALESCE(water_ml, 0) >= 2000),
        COUNT(*) FILTER (WHERE COALESCE(fasting_hours, 0) > 0)
    INTO v_avg_calories, v_avg_protein, v_water_days, v_fasting_days
    FROM life.daily_facts
    WHERE day BETWEEN v_week_start AND v_week_end;

    -- =========================================================================
    -- BJJ
    -- =========================================================================
    SELECT COUNT(*) INTO v_bjj_sessions
    FROM health.bjj_sessions
    WHERE session_date BETWEEN v_week_start AND v_week_end;

    BEGIN
        SELECT current_streak INTO v_bjj_streak FROM health.get_bjj_streaks();
    EXCEPTION WHEN OTHERS THEN
        v_bjj_streak := 0;
    END;

    -- =========================================================================
    -- WORK HOURS from v_work_sessions
    -- =========================================================================
    BEGIN
        SELECT COALESCE(AVG(daily_hours), 0)
        INTO v_avg_work_hours
        FROM (
            SELECT
                ws.session_date,
                SUM(EXTRACT(EPOCH FROM (COALESCE(ws.departed_at, NOW()) - ws.arrived_at)) / 3600) AS daily_hours
            FROM life.v_work_sessions ws
            WHERE ws.session_date BETWEEN v_week_start AND v_week_end
            GROUP BY ws.session_date
        ) daily_work;
    EXCEPTION WHEN OTHERS THEN
        v_avg_work_hours := 0;
    END;

    -- =========================================================================
    -- FINANCE from daily_facts
    -- =========================================================================
    SELECT
        COALESCE(SUM(spend_total), 0),
        COALESCE(SUM(income_total), 0)
    INTO v_total_spent, v_total_income
    FROM life.daily_facts
    WHERE day BETWEEN v_week_start AND v_week_end;

    -- Previous week for trend
    SELECT COALESCE(SUM(spend_total), 0)
    INTO v_prev_week_spent
    FROM life.daily_facts
    WHERE day BETWEEN v_week_start - 7 AND v_week_start - 1;

    v_spending_trend := CASE
        WHEN v_prev_week_spent = 0 THEN 'no_data'
        WHEN v_total_spent > v_prev_week_spent * 1.2 THEN 'increasing'
        WHEN v_total_spent < v_prev_week_spent * 0.8 THEN 'decreasing'
        ELSE 'stable'
    END;

    -- Top spending category (aggregate across week)
    BEGIN
        SELECT key INTO v_top_category
        FROM (
            SELECT key, SUM(value::numeric) AS total
            FROM life.daily_facts df,
                 jsonb_each_text(df.spending_by_category)
            WHERE df.day BETWEEN v_week_start AND v_week_end
              AND df.spending_by_category IS NOT NULL
            GROUP BY key
            ORDER BY total DESC
            LIMIT 1
        ) top_cat;
    EXCEPTION WHEN OTHERS THEN
        v_top_category := NULL;
    END;

    -- =========================================================================
    -- PRODUCTIVITY
    -- =========================================================================
    BEGIN
        SELECT total_commits, active_days
        INTO v_total_commits, v_active_days
        FROM insights.v_weekly_productivity
        WHERE week_start = v_week_start;
    EXCEPTION WHEN OTHERS THEN
        v_total_commits := 0;
        v_active_days := 0;
    END;

    -- =========================================================================
    -- HABIT COMPLETION (4 habits: water, meals, weight, workout)
    -- Each habit = 25% of day; avg across week
    -- =========================================================================
    SELECT ROUND(
        AVG(
            (CASE WHEN COALESCE(water_ml, 0) > 0 THEN 25.0 ELSE 0 END) +
            (CASE WHEN COALESCE(meals_logged, 0) > 0 THEN 25.0 ELSE 0 END) +
            (CASE WHEN weight_kg IS NOT NULL THEN 25.0 ELSE 0 END) +
            (CASE WHEN COALESCE(workout_count, 0) > 0 THEN 25.0 ELSE 0 END)
        ), 1
    ) INTO v_habit_completion_pct
    FROM life.daily_facts
    WHERE day BETWEEN v_week_start AND v_week_end;

    -- =========================================================================
    -- ALERTS
    -- =========================================================================
    BEGIN
        SELECT COUNT(*) INTO v_anomaly_count
        FROM insights.daily_anomalies
        WHERE day BETWEEN v_week_start AND v_week_end;
    EXCEPTION WHEN OTHERS THEN
        v_anomaly_count := 0;
    END;

    v_critical_alerts := 0;
    v_budget_alerts := 0;

    -- =========================================================================
    -- COMPOSITE SCORE (0-10, each category 0-2)
    -- =========================================================================
    v_score := 0;

    -- Recovery: >= 60 → +2, >= 40 → +1
    IF COALESCE(v_avg_recovery, 0) >= 60 THEN v_score := v_score + 2;
    ELSIF COALESCE(v_avg_recovery, 0) >= 40 THEN v_score := v_score + 1;
    END IF;

    -- Sleep: >= 7h → +2, >= 6h → +1
    IF COALESCE(v_avg_sleep_hours, 0) >= 7 THEN v_score := v_score + 2;
    ELSIF COALESCE(v_avg_sleep_hours, 0) >= 6 THEN v_score := v_score + 1;
    END IF;

    -- BJJ: >= 2 sessions → +2, >= 1 → +1
    IF COALESCE(v_bjj_sessions, 0) >= 2 THEN v_score := v_score + 2;
    ELSIF COALESCE(v_bjj_sessions, 0) >= 1 THEN v_score := v_score + 1;
    END IF;

    -- Spending: under prev week → +2, within 10% → +1
    IF v_prev_week_spent > 0 AND v_total_spent <= v_prev_week_spent THEN v_score := v_score + 2;
    ELSIF v_prev_week_spent > 0 AND v_total_spent <= v_prev_week_spent * 1.1 THEN v_score := v_score + 1;
    END IF;

    -- Habits: >= 80% → +2, >= 50% → +1
    IF COALESCE(v_habit_completion_pct, 0) >= 80 THEN v_score := v_score + 2;
    ELSIF COALESCE(v_habit_completion_pct, 0) >= 50 THEN v_score := v_score + 1;
    END IF;

    -- =========================================================================
    -- COACH-TONE SUMMARY
    -- =========================================================================
    v_summary_text := '';

    -- Opening
    IF v_score >= 8 THEN
        v_summary_text := 'Outstanding week. ';
    ELSIF v_score >= 6 THEN
        v_summary_text := 'Solid week overall. ';
    ELSIF v_score >= 4 THEN
        v_summary_text := 'Decent week with room to grow. ';
    ELSE
        v_summary_text := 'Tough week. Reset and come back stronger. ';
    END IF;

    -- Recovery
    IF v_avg_recovery IS NOT NULL THEN
        v_summary_text := v_summary_text || format('Recovery averaged %s%%', ROUND(v_avg_recovery));
        IF v_recovery_trend = 'improving' THEN
            v_summary_text := v_summary_text || ' and trending up. ';
        ELSIF v_recovery_trend = 'declining' THEN
            v_summary_text := v_summary_text || ', down from last week. ';
        ELSE
            v_summary_text := v_summary_text || '. ';
        END IF;
    END IF;

    -- Sleep
    IF v_avg_sleep_hours IS NOT NULL THEN
        IF v_avg_sleep_hours >= 7 THEN
            v_summary_text := v_summary_text || format('Sleep solid at %sh avg. ', ROUND(v_avg_sleep_hours, 1));
        ELSE
            v_summary_text := v_summary_text || format('Sleep needs work at %sh avg. ', ROUND(v_avg_sleep_hours, 1));
        END IF;
    END IF;

    -- BJJ
    IF v_bjj_sessions > 0 THEN
        v_summary_text := v_summary_text || format('%s BJJ session%s', v_bjj_sessions, CASE WHEN v_bjj_sessions > 1 THEN 's' ELSE '' END);
        IF v_bjj_streak > 1 THEN
            v_summary_text := v_summary_text || format(' (%s-week streak)', v_bjj_streak);
        END IF;
        v_summary_text := v_summary_text || '. ';
    END IF;

    -- Finance
    IF v_total_spent > 0 THEN
        v_summary_text := v_summary_text || format('Spent %s AED', ROUND(v_total_spent));
        IF v_spending_trend = 'increasing' THEN
            v_summary_text := v_summary_text || ', up from last week. ';
        ELSIF v_spending_trend = 'decreasing' THEN
            v_summary_text := v_summary_text || ', down from last week. ';
        ELSE
            v_summary_text := v_summary_text || '. ';
        END IF;
    END IF;

    -- Habits
    IF v_habit_completion_pct IS NOT NULL THEN
        IF v_habit_completion_pct >= 80 THEN
            v_summary_text := v_summary_text || format('Habits on point at %s%%.', ROUND(v_habit_completion_pct));
        ELSIF v_habit_completion_pct >= 50 THEN
            v_summary_text := v_summary_text || format('Habit consistency at %s%% — push for more.', ROUND(v_habit_completion_pct));
        ELSE
            v_summary_text := v_summary_text || format('Habits dropped to %s%% — rebuild the routine.', ROUND(v_habit_completion_pct));
        END IF;
    END IF;

    -- =========================================================================
    -- HIGHLIGHTS + MARKDOWN
    -- =========================================================================
    v_highlights := jsonb_build_object(
        'health_trend', v_recovery_trend,
        'spending_trend', v_spending_trend,
        'top_insight', CASE
            WHEN COALESCE(v_avg_recovery, 0) < 50 THEN 'Low recovery week'
            WHEN v_total_spent > 5000 THEN 'High spending week'
            WHEN v_bjj_sessions >= 3 THEN 'Great training week'
            WHEN COALESCE(v_total_commits, 0) > 50 THEN 'Productive coding week'
            ELSE 'Normal week'
        END
    );

    v_markdown := format(
        E'# Weekly Review\n' ||
        E'**Week:** %s to %s | **Score:** %s/10\n\n---\n\n' ||
        E'## Summary\n%s\n\n' ||
        E'## Health\n- Recovery: %s%%\n- HRV: %s\n- Sleep: %sh/night\n- BJJ: %s sessions\n\n' ||
        E'## Nutrition\n- Avg Calories: %s\n- Avg Protein: %sg\n- Water Days (2L+): %s/7\n- Fasting Days: %s/7\n\n' ||
        E'## Finance\n- Spent: %s AED\n- Income: %s AED\n- Top Category: %s\n\n' ||
        E'## Work & Habits\n- Avg Work: %sh\n- Habits: %s%%\n- Coding Days: %s\n\n---\n*Generated: %s*\n',
        v_week_start, v_week_end, v_score,
        v_summary_text,
        COALESCE(ROUND(v_avg_recovery)::text, 'N/A'),
        COALESCE(ROUND(v_avg_hrv)::text, 'N/A'),
        COALESCE(ROUND(v_avg_sleep_hours, 1)::text, 'N/A'),
        COALESCE(v_bjj_sessions::text, '0'),
        COALESCE(v_avg_calories::text, 'N/A'),
        COALESCE(v_avg_protein::text, 'N/A'),
        COALESCE(v_water_days::text, '0'),
        COALESCE(v_fasting_days::text, '0'),
        COALESCE(ROUND(v_total_spent)::text, '0'),
        COALESCE(ROUND(v_total_income)::text, '0'),
        COALESCE(v_top_category, 'N/A'),
        COALESCE(ROUND(v_avg_work_hours, 1)::text, '0'),
        COALESCE(ROUND(v_habit_completion_pct)::text, '0'),
        COALESCE(v_active_days::text, '0'),
        NOW()::text
    );

    -- =========================================================================
    -- UPSERT
    -- =========================================================================
    INSERT INTO insights.weekly_reports (
        week_start, week_end,
        avg_recovery, avg_hrv, avg_sleep_hours, recovery_trend,
        total_spent, total_income, top_category, budget_alerts, spending_trend,
        total_commits, active_days, productivity_trend,
        anomaly_count, critical_alerts,
        markdown_report, highlights,
        score, bjj_sessions, bjj_streak,
        avg_calories, avg_protein, water_days, fasting_days,
        avg_work_hours, habit_completion_pct, summary_text
    ) VALUES (
        v_week_start, v_week_end,
        v_avg_recovery, v_avg_hrv, v_avg_sleep_hours, v_recovery_trend,
        v_total_spent, v_total_income, v_top_category, v_budget_alerts, v_spending_trend,
        v_total_commits, v_active_days, NULL,
        v_anomaly_count, v_critical_alerts,
        v_markdown, v_highlights,
        v_score, v_bjj_sessions, v_bjj_streak,
        v_avg_calories, v_avg_protein, v_water_days, v_fasting_days,
        v_avg_work_hours, v_habit_completion_pct, v_summary_text
    )
    ON CONFLICT (week_start) DO UPDATE SET
        week_end = EXCLUDED.week_end,
        avg_recovery = EXCLUDED.avg_recovery,
        avg_hrv = EXCLUDED.avg_hrv,
        avg_sleep_hours = EXCLUDED.avg_sleep_hours,
        recovery_trend = EXCLUDED.recovery_trend,
        total_spent = EXCLUDED.total_spent,
        total_income = EXCLUDED.total_income,
        top_category = EXCLUDED.top_category,
        budget_alerts = EXCLUDED.budget_alerts,
        spending_trend = EXCLUDED.spending_trend,
        total_commits = EXCLUDED.total_commits,
        active_days = EXCLUDED.active_days,
        anomaly_count = EXCLUDED.anomaly_count,
        critical_alerts = EXCLUDED.critical_alerts,
        markdown_report = EXCLUDED.markdown_report,
        highlights = EXCLUDED.highlights,
        score = EXCLUDED.score,
        bjj_sessions = EXCLUDED.bjj_sessions,
        bjj_streak = EXCLUDED.bjj_streak,
        avg_calories = EXCLUDED.avg_calories,
        avg_protein = EXCLUDED.avg_protein,
        water_days = EXCLUDED.water_days,
        fasting_days = EXCLUDED.fasting_days,
        avg_work_hours = EXCLUDED.avg_work_hours,
        habit_completion_pct = EXCLUDED.habit_completion_pct,
        summary_text = EXCLUDED.summary_text,
        generated_at = NOW()
    RETURNING id INTO v_report_id;

    RETURN v_report_id;
END;
$$;

-- 3. Update dashboard.get_payload() to v20 with latest_weekly_review
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

    -- Build final result (schema_version 20: Added latest_weekly_review)
    result := jsonb_build_object(
        'schema_version', 20, 'generated_at', NOW(), 'target_date', the_date,
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
        'latest_weekly_review', weekly_review_data
    );

    RETURN result;
END;
$$;

INSERT INTO ops.schema_migrations (filename) VALUES ('186_weekly_review_v2.up.sql');

COMMIT;
