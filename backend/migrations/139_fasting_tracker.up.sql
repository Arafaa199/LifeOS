-- Migration 139: Simple fasting tracker
-- Two buttons: Start Fast / Break Fast. Shows elapsed time.

BEGIN;

-- =============================================================================
-- 1. Fasting sessions table
-- =============================================================================

CREATE TABLE IF NOT EXISTS health.fasting_sessions (
    id SERIAL PRIMARY KEY,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    duration_hours NUMERIC(5,2) GENERATED ALWAYS AS (
        CASE WHEN ended_at IS NOT NULL
             THEN EXTRACT(EPOCH FROM (ended_at - started_at)) / 3600
             ELSE NULL
        END
    ) STORED,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_fasting_sessions_started ON health.fasting_sessions(started_at DESC);

COMMENT ON TABLE health.fasting_sessions IS 'Simple fasting tracker. One active session at a time (ended_at IS NULL).';

-- =============================================================================
-- 2. Helper functions
-- =============================================================================

-- Get current fasting status
CREATE OR REPLACE FUNCTION health.get_fasting_status()
RETURNS JSONB AS $$
DECLARE
    active_session RECORD;
    elapsed_hours NUMERIC(5,2);
BEGIN
    SELECT id, started_at, ended_at
    INTO active_session
    FROM health.fasting_sessions
    WHERE ended_at IS NULL
    ORDER BY started_at DESC
    LIMIT 1;

    IF active_session.id IS NULL THEN
        -- No active fast
        RETURN jsonb_build_object(
            'is_active', false,
            'started_at', NULL,
            'elapsed_hours', NULL
        );
    ELSE
        elapsed_hours := ROUND(EXTRACT(EPOCH FROM (NOW() - active_session.started_at)) / 3600, 2);
        RETURN jsonb_build_object(
            'is_active', true,
            'session_id', active_session.id,
            'started_at', active_session.started_at,
            'elapsed_hours', elapsed_hours
        );
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;

-- Start a fast (ends any active fast first)
CREATE OR REPLACE FUNCTION health.start_fast()
RETURNS JSONB AS $$
DECLARE
    new_id INT;
BEGIN
    -- End any active fast first
    UPDATE health.fasting_sessions
    SET ended_at = NOW()
    WHERE ended_at IS NULL;

    -- Start new fast
    INSERT INTO health.fasting_sessions (started_at)
    VALUES (NOW())
    RETURNING id INTO new_id;

    RETURN jsonb_build_object(
        'success', true,
        'session_id', new_id,
        'started_at', NOW()
    );
END;
$$ LANGUAGE plpgsql;

-- Break the fast (end active session)
CREATE OR REPLACE FUNCTION health.break_fast()
RETURNS JSONB AS $$
DECLARE
    active_session RECORD;
    final_hours NUMERIC(5,2);
BEGIN
    SELECT id, started_at
    INTO active_session
    FROM health.fasting_sessions
    WHERE ended_at IS NULL
    ORDER BY started_at DESC
    LIMIT 1;

    IF active_session.id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'No active fast to break'
        );
    END IF;

    UPDATE health.fasting_sessions
    SET ended_at = NOW()
    WHERE id = active_session.id;

    final_hours := ROUND(EXTRACT(EPOCH FROM (NOW() - active_session.started_at)) / 3600, 2);

    RETURN jsonb_build_object(
        'success', true,
        'session_id', active_session.id,
        'duration_hours', final_hours
    );
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- 3. Add fasting to dashboard payload
-- =============================================================================

-- Update dashboard.get_payload to include fasting status
-- (Adding to the existing function - find and update)

CREATE OR REPLACE FUNCTION dashboard.get_payload(for_date DATE DEFAULT NULL)
RETURNS JSONB AS $$
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
BEGIN
    the_date := COALESCE(for_date, life.dubai_today());

    -- Get daily facts
    SELECT * INTO facts_row FROM life.daily_facts WHERE day = the_date;

    -- Get finance summary
    SELECT jsonb_build_object(
        'spend_total', COALESCE(facts_row.spend_total, 0),
        'spend_groceries', COALESCE(facts_row.spend_groceries, 0),
        'spend_restaurants', COALESCE(facts_row.spend_restaurants, 0),
        'spend_transport', COALESCE(facts_row.spend_transport, 0),
        'income_total', COALESCE(facts_row.income_total, 0),
        'transaction_count', COALESCE(facts_row.transaction_count, 0)
    ) INTO finance_data;

    -- Get feed status
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'feed', source,
            'status', status,
            'lastSync', last_event_at,
            'hoursSinceSync', EXTRACT(EPOCH FROM (NOW() - last_event_at)) / 3600
        )
    ), '[]'::jsonb)
    INTO feed_data
    FROM life.feed_status;

    -- Get daily insights (get_ranked_insights returns JSONB directly)
    SELECT COALESCE(insights.get_ranked_insights(the_date), '{}'::jsonb) INTO insights_data;

    -- Get calendar summary
    SELECT COALESCE(
        (SELECT jsonb_build_object(
            'meeting_count', meeting_count,
            'meeting_hours', meeting_hours,
            'first_meeting', first_meeting,
            'last_meeting', last_meeting
        ) FROM life.v_daily_calendar_summary WHERE day = the_date),
        jsonb_build_object('meeting_count', 0, 'meeting_hours', 0, 'first_meeting', NULL, 'last_meeting', NULL)
    ) INTO calendar_data;

    -- Get reminder summary
    SELECT jsonb_build_object(
        'due_today', COALESCE(facts_row.reminders_due, 0),
        'completed_today', COALESCE(facts_row.reminders_completed, 0),
        'overdue_count', (SELECT COUNT(*) FROM raw.reminders
                          WHERE deleted_at IS NULL
                          AND is_completed = false
                          AND due_date < the_date)::int
    ) INTO reminder_data;

    -- Get GitHub activity
    SELECT COALESCE(life.get_github_activity_widget(14), '{}'::jsonb) INTO github_data;

    -- Get fasting status
    SELECT health.get_fasting_status() INTO fasting_data;

    -- Build result
    result := jsonb_build_object(
        'schema_version', 9,
        'generated_at', NOW(),
        'target_date', the_date,
        'today_facts', jsonb_build_object(
            'day', the_date,
            'recovery_score', facts_row.recovery_score,
            'hrv', facts_row.hrv,
            'rhr', facts_row.rhr,
            'sleep_minutes', facts_row.sleep_minutes,
            'sleep_hours', facts_row.sleep_hours,
            'deep_sleep_hours', facts_row.deep_sleep_hours,
            'sleep_efficiency', facts_row.sleep_efficiency,
            'strain', facts_row.strain,
            'weight_kg', facts_row.weight_kg,
            'spend_total', facts_row.spend_total,
            'spend_vs_7d', ROUND(((facts_row.spend_total - (
                SELECT AVG(spend_total) FROM life.daily_facts
                WHERE day BETWEEN the_date - 7 AND the_date - 1
            )) / NULLIF((
                SELECT AVG(spend_total) FROM life.daily_facts
                WHERE day BETWEEN the_date - 7 AND the_date - 1
            ), 0) * 100)::numeric, 1),
            'spend_unusual', facts_row.spend_total > COALESCE((
                SELECT AVG(spend_total) + 2 * STDDEV(spend_total)
                FROM life.daily_facts
                WHERE day BETWEEN the_date - 30 AND the_date - 1
            ), 9999),
            'meals_logged', COALESCE(facts_row.meals_logged, 0),
            'water_ml', COALESCE(facts_row.water_ml, 0),
            'calories_consumed', facts_row.calories_consumed,
            'protein_g', facts_row.protein_g,
            'data_completeness', facts_row.data_completeness
        ),
        'finance_summary', finance_data,
        'feed_status', feed_data,
        'stale_feeds', (
            SELECT COALESCE(array_agg(source), '{}')
            FROM life.feed_status
            WHERE status IN ('stale', 'error')
        ),
        'daily_insights', insights_data,
        'calendar_summary', calendar_data,
        'reminder_summary', reminder_data,
        'github_activity', github_data,
        'fasting', fasting_data
    );

    RETURN result;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION dashboard.get_payload IS 'Main dashboard payload. Schema v9: Added fasting status.';

COMMIT;
