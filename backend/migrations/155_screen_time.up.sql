BEGIN;

-- Migration 155: Screen Time tracking
-- Data comes from iOS Shortcuts automation (daily POST to n8n webhook)

-- Screen time history table
CREATE TABLE IF NOT EXISTS life.screen_time_daily (
    date DATE PRIMARY KEY,
    total_minutes INT NOT NULL,
    social_minutes INT,
    entertainment_minutes INT,
    productivity_minutes INT,
    reading_minutes INT,
    other_minutes INT,
    pickups INT,
    first_pickup_at TIMESTAMPTZ,
    raw_json JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

GRANT SELECT, INSERT, UPDATE ON life.screen_time_daily TO nexus;

-- Add screen time column to daily_facts
ALTER TABLE life.daily_facts
ADD COLUMN IF NOT EXISTS screen_time_hours NUMERIC(4,1);

-- Function to update daily_facts with screen time
CREATE OR REPLACE FUNCTION life.update_daily_facts_screen_time(p_date DATE)
RETURNS VOID AS $$
BEGIN
    UPDATE life.daily_facts df
    SET screen_time_hours = ROUND(st.total_minutes / 60.0, 1)
    FROM life.screen_time_daily st
    WHERE df.day = p_date AND st.date = p_date;
END;
$$ LANGUAGE plpgsql;

-- Add feed status entry for screen_time
INSERT INTO life.feed_status_live (source, expected_interval)
VALUES ('screen_time', '48:00:00')
ON CONFLICT (source) DO NOTHING;

COMMENT ON TABLE life.screen_time_daily IS 'Daily screen time data from iOS Shortcuts automation';

INSERT INTO ops.schema_migrations (filename) VALUES ('155_screen_time.up.sql')
ON CONFLICT (filename) DO NOTHING;

COMMIT;
