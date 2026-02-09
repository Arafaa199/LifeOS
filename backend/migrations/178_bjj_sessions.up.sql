-- Migration 178: Create BJJ sessions table
-- Tracks Brazilian Jiu-Jitsu training sessions with optional Whoop integration

CREATE TABLE IF NOT EXISTS health.bjj_sessions (
    id SERIAL PRIMARY KEY,
    session_date DATE NOT NULL UNIQUE,
    session_type TEXT NOT NULL DEFAULT 'bjj' CHECK (session_type IN ('bjj', 'nogi', 'mma')),
    duration_minutes INTEGER DEFAULT 60,
    start_time TIME,
    end_time TIME,

    -- Whoop integration (nullable, populated when matched)
    strain DOUBLE PRECISION,
    hr_avg INTEGER,
    calories INTEGER,

    -- Source tracking
    source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'auto_location', 'auto_whoop', 'notification')),

    -- Session details
    techniques TEXT[],
    notes TEXT,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for date queries and streak calculations
CREATE INDEX IF NOT EXISTS idx_bjj_sessions_date ON health.bjj_sessions(session_date DESC);

-- Trigger for updated_at
CREATE OR REPLACE FUNCTION health.update_bjj_sessions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_bjj_sessions_updated_at ON health.bjj_sessions;
CREATE TRIGGER trg_bjj_sessions_updated_at
    BEFORE UPDATE ON health.bjj_sessions
    FOR EACH ROW
    EXECUTE FUNCTION health.update_bjj_sessions_updated_at();

-- Helper function to calculate BJJ streaks
CREATE OR REPLACE FUNCTION health.get_bjj_streaks()
RETURNS TABLE (
    current_streak INTEGER,
    longest_streak INTEGER,
    total_sessions BIGINT,
    sessions_this_month BIGINT,
    sessions_this_week BIGINT
) AS $$
DECLARE
    v_current_streak INTEGER := 0;
    v_longest_streak INTEGER := 0;
    v_streak INTEGER := 0;
    v_prev_date DATE;
    v_session RECORD;
BEGIN
    -- Calculate current streak (consecutive weeks with at least one session)
    -- A "streak" = consecutive weeks where you trained at least once
    FOR v_session IN
        SELECT DISTINCT date_trunc('week', session_date)::date as week_start
        FROM health.bjj_sessions
        ORDER BY week_start DESC
    LOOP
        IF v_prev_date IS NULL THEN
            v_streak := 1;
            v_prev_date := v_session.week_start;
        ELSIF v_prev_date - v_session.week_start = 7 THEN
            v_streak := v_streak + 1;
            v_prev_date := v_session.week_start;
        ELSE
            EXIT;
        END IF;
    END LOOP;

    v_current_streak := v_streak;

    -- Calculate longest streak
    v_streak := 0;
    v_prev_date := NULL;
    FOR v_session IN
        SELECT DISTINCT date_trunc('week', session_date)::date as week_start
        FROM health.bjj_sessions
        ORDER BY week_start ASC
    LOOP
        IF v_prev_date IS NULL THEN
            v_streak := 1;
            v_prev_date := v_session.week_start;
        ELSIF v_session.week_start - v_prev_date = 7 THEN
            v_streak := v_streak + 1;
            v_prev_date := v_session.week_start;
        ELSE
            IF v_streak > v_longest_streak THEN
                v_longest_streak := v_streak;
            END IF;
            v_streak := 1;
            v_prev_date := v_session.week_start;
        END IF;
    END LOOP;

    IF v_streak > v_longest_streak THEN
        v_longest_streak := v_streak;
    END IF;

    RETURN QUERY
    SELECT
        v_current_streak,
        v_longest_streak,
        (SELECT COUNT(*) FROM health.bjj_sessions),
        (SELECT COUNT(*) FROM health.bjj_sessions
         WHERE session_date >= date_trunc('month', CURRENT_DATE)),
        (SELECT COUNT(*) FROM health.bjj_sessions
         WHERE session_date >= date_trunc('week', CURRENT_DATE));
END;
$$ LANGUAGE plpgsql;

COMMENT ON TABLE health.bjj_sessions IS 'BJJ/MMA training session log with optional Whoop metrics';
COMMENT ON COLUMN health.bjj_sessions.session_type IS 'Type: bjj (gi), nogi (no-gi), mma';
COMMENT ON COLUMN health.bjj_sessions.source IS 'How session was logged: manual, auto_location (geo-fence), auto_whoop (strain match), notification (iOS prompt)';
COMMENT ON COLUMN health.bjj_sessions.techniques IS 'Array of techniques practiced (e.g., ["armbar", "triangle", "guard passing"])';
