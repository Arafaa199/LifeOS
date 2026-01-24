-- Migration: 024_behavioral_events
-- Adds behavioral events table for sleep/wake detection and device usage tracking
-- TASK-058: Sleep Behavior Detection
-- TASK-060: TV Watch Session Tracking

-- ============================================================================
-- life.behavioral_events - Store behavioral signals
-- ============================================================================

CREATE TABLE IF NOT EXISTS life.behavioral_events (
    id BIGSERIAL PRIMARY KEY,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_type TEXT NOT NULL CHECK (event_type IN (
        'sleep_detected',
        'wake_detected',
        'tv_session_start',
        'tv_session_end',
        'motion_detected',
        'motion_stopped',
        'screen_time_start',
        'screen_time_end'
    )),
    source TEXT NOT NULL DEFAULT 'home_assistant',
    duration_minutes INTEGER,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_behavioral_events_recorded_at ON life.behavioral_events(recorded_at DESC);
CREATE INDEX idx_behavioral_events_event_type ON life.behavioral_events(event_type);
CREATE INDEX idx_behavioral_events_day ON life.behavioral_events(((recorded_at AT TIME ZONE 'Asia/Dubai')::date));

-- ============================================================================
-- life.daily_behavioral_summary - Aggregate daily behavioral metrics
-- ============================================================================

CREATE OR REPLACE VIEW life.daily_behavioral_summary AS
WITH tv_sessions AS (
    SELECT
        (recorded_at AT TIME ZONE 'Asia/Dubai')::date AS day,
        SUM(duration_minutes) AS tv_minutes,
        COUNT(*) FILTER (WHERE event_type = 'tv_session_end') AS tv_sessions
    FROM life.behavioral_events
    WHERE event_type IN ('tv_session_start', 'tv_session_end')
      AND recorded_at >= NOW() - INTERVAL '90 days'
    GROUP BY 1
),
sleep_events AS (
    SELECT
        (recorded_at AT TIME ZONE 'Asia/Dubai')::date AS day,
        MIN(CASE WHEN event_type = 'sleep_detected' THEN recorded_at END) AS sleep_detected_at,
        MIN(CASE WHEN event_type = 'wake_detected' THEN recorded_at END) AS wake_detected_at
    FROM life.behavioral_events
    WHERE event_type IN ('sleep_detected', 'wake_detected')
      AND recorded_at >= NOW() - INTERVAL '90 days'
    GROUP BY 1
)
SELECT
    COALESCE(t.day, s.day) AS day,
    ROUND(COALESCE(t.tv_minutes, 0) / 60.0, 2) AS tv_hours,
    t.tv_sessions,
    s.sleep_detected_at,
    s.wake_detected_at,
    -- Evening TV watching (after 8pm) correlates with later sleep
    COALESCE((
        SELECT SUM(duration_minutes)
        FROM life.behavioral_events be
        WHERE event_type = 'tv_session_end'
          AND (be.recorded_at AT TIME ZONE 'Asia/Dubai')::date = COALESCE(t.day, s.day)
          AND EXTRACT(HOUR FROM (be.recorded_at AT TIME ZONE 'Asia/Dubai')) >= 20
    ), 0) AS evening_tv_minutes
FROM tv_sessions t
FULL OUTER JOIN sleep_events s ON t.day = s.day
ORDER BY day DESC;

-- ============================================================================
-- Function to log TV session with duration calculation
-- ============================================================================

CREATE OR REPLACE FUNCTION life.log_tv_session_end()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $function$
DECLARE
    v_session_start TIMESTAMPTZ;
    v_duration_minutes INTEGER;
BEGIN
    -- Find the most recent session start
    SELECT recorded_at INTO v_session_start
    FROM life.behavioral_events
    WHERE event_type = 'tv_session_start'
      AND recorded_at < NEW.recorded_at
    ORDER BY recorded_at DESC
    LIMIT 1;

    IF v_session_start IS NOT NULL THEN
        v_duration_minutes := EXTRACT(EPOCH FROM (NEW.recorded_at - v_session_start)) / 60;
        NEW.duration_minutes := v_duration_minutes;
    END IF;

    RETURN NEW;
END;
$function$;

CREATE TRIGGER tr_calculate_tv_duration
    BEFORE INSERT ON life.behavioral_events
    FOR EACH ROW
    WHEN (NEW.event_type = 'tv_session_end')
    EXECUTE FUNCTION life.log_tv_session_end();

-- ============================================================================
-- Function to ingest behavioral event
-- ============================================================================

CREATE OR REPLACE FUNCTION life.ingest_behavioral_event(
    p_event_type TEXT,
    p_source TEXT DEFAULT 'home_assistant',
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id BIGINT;
BEGIN
    INSERT INTO life.behavioral_events (
        recorded_at,
        event_type,
        source,
        metadata
    ) VALUES (
        NOW(),
        p_event_type,
        p_source,
        p_metadata
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$function$;

-- Grant permissions
GRANT SELECT, INSERT ON life.behavioral_events TO nexus;
GRANT USAGE, SELECT ON SEQUENCE life.behavioral_events_id_seq TO nexus;
GRANT SELECT ON life.daily_behavioral_summary TO nexus;
GRANT EXECUTE ON FUNCTION life.ingest_behavioral_event(TEXT, TEXT, JSONB) TO nexus;

COMMENT ON TABLE life.behavioral_events IS 'Behavioral signals: sleep/wake detection, TV sessions, screen time';
COMMENT ON VIEW life.daily_behavioral_summary IS 'Daily behavioral metrics - TV hours, sleep detection times';
COMMENT ON FUNCTION life.ingest_behavioral_event IS 'Ingest a behavioral event (sleep, wake, tv_session, etc.)';
