-- Migration 068: Calendar Schema Prep (Backend Only)
-- Objective: Define schema + webhook contract for calendar ingestion
-- Context: iOS EventKit will eventually POST calendar events - backend must be ready first

-- Create raw.calendar_events table
CREATE TABLE IF NOT EXISTS raw.calendar_events (
    id SERIAL PRIMARY KEY,
    event_id VARCHAR(255) NOT NULL,
    title VARCHAR(500),
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ NOT NULL,
    is_all_day BOOLEAN DEFAULT false,
    calendar_name VARCHAR(255),
    location VARCHAR(500),
    notes TEXT,
    recurrence_rule TEXT,
    client_id UUID,
    source VARCHAR(50) DEFAULT 'ios_eventkit',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    -- Idempotency: unique constraint on (event_id, source)
    CONSTRAINT uq_calendar_events_event_id_source UNIQUE (event_id, source)
);

-- Create index for common queries
CREATE INDEX IF NOT EXISTS idx_calendar_events_start_at ON raw.calendar_events(start_at);
CREATE INDEX IF NOT EXISTS idx_calendar_events_client_id ON raw.calendar_events(client_id) WHERE client_id IS NOT NULL;

-- Create view for daily calendar summary
CREATE OR REPLACE VIEW life.v_daily_calendar_summary AS
SELECT
    (start_at AT TIME ZONE 'Asia/Dubai')::DATE as day,
    COUNT(*) as meeting_count,
    ROUND(SUM(EXTRACT(EPOCH FROM (end_at - start_at)) / 3600.0)::NUMERIC, 2) as meeting_hours,
    MIN(start_at AT TIME ZONE 'Asia/Dubai')::TIME as first_meeting,
    MAX(start_at AT TIME ZONE 'Asia/Dubai')::TIME as last_meeting
FROM raw.calendar_events
WHERE is_all_day = false  -- Exclude all-day events from meeting stats
GROUP BY (start_at AT TIME ZONE 'Asia/Dubai')::DATE
ORDER BY day DESC;

-- Add comment
COMMENT ON TABLE raw.calendar_events IS 'Calendar events from iOS EventKit - backend schema ready, iOS integration deferred';
COMMENT ON VIEW life.v_daily_calendar_summary IS 'Daily calendar summary: meeting count, hours, first/last meeting times';
