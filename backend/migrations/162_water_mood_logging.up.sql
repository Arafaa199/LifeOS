-- Migration 162: Water & Mood Logging Backend
-- Creates tables for water intake and mood/energy tracking

-- ============================================
-- WATER LOGGING
-- ============================================

CREATE TABLE IF NOT EXISTS nutrition.water_log (
    id              SERIAL PRIMARY KEY,
    date            DATE NOT NULL DEFAULT (NOW() AT TIME ZONE 'Asia/Dubai')::date,
    amount_ml       INT NOT NULL CHECK (amount_ml > 0 AND amount_ml <= 10000),
    logged_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    source          TEXT NOT NULL DEFAULT 'ios-app',
    client_id       UUID,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(client_id)  -- Idempotency
);

CREATE INDEX idx_water_log_date ON nutrition.water_log (date DESC);

-- Feed status for water
INSERT INTO life.feed_status_live (source, last_event_at, events_today, expected_interval)
VALUES ('water', NULL, 0, INTERVAL '24 hours')
ON CONFLICT (source) DO NOTHING;

-- Trigger to update feed status on water log insert
CREATE OR REPLACE FUNCTION nutrition.update_water_feed_status()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO life.feed_status_live (source, last_event_at, events_today, expected_interval)
    VALUES ('water', NOW(), 1, INTERVAL '24 hours')
    ON CONFLICT (source) DO UPDATE SET
        last_event_at = NOW(),
        events_today = CASE
            WHEN (life.feed_status_live.last_event_at AT TIME ZONE 'Asia/Dubai')::date = (NOW() AT TIME ZONE 'Asia/Dubai')::date
            THEN life.feed_status_live.events_today + 1
            ELSE 1
        END;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_water_log_feed_status
    AFTER INSERT ON nutrition.water_log
    FOR EACH ROW EXECUTE FUNCTION nutrition.update_water_feed_status();

-- Daily water summary view
CREATE OR REPLACE VIEW nutrition.v_daily_water_summary AS
SELECT
    date,
    SUM(amount_ml) as total_ml,
    COUNT(*) as log_count,
    MAX(logged_at) as last_logged_at
FROM nutrition.water_log
GROUP BY date;

-- ============================================
-- MOOD & ENERGY LOGGING
-- ============================================

CREATE TABLE IF NOT EXISTS raw.mood_log (
    id              SERIAL PRIMARY KEY,
    date            DATE NOT NULL DEFAULT (NOW() AT TIME ZONE 'Asia/Dubai')::date,
    logged_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    mood_score      INT NOT NULL CHECK (mood_score >= 1 AND mood_score <= 10),
    energy_score    INT CHECK (energy_score >= 1 AND energy_score <= 10),
    notes           TEXT,
    source          TEXT NOT NULL DEFAULT 'ios-app',
    client_id       UUID,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(client_id)  -- Idempotency
);

CREATE INDEX idx_mood_log_date ON raw.mood_log (date DESC);
CREATE INDEX idx_mood_log_logged_at ON raw.mood_log (logged_at DESC);

-- Feed status for mood
INSERT INTO life.feed_status_live (source, last_event_at, events_today, expected_interval)
VALUES ('mood', NULL, 0, INTERVAL '24 hours')
ON CONFLICT (source) DO NOTHING;

-- Trigger to update feed status on mood log insert
CREATE OR REPLACE FUNCTION raw.update_mood_feed_status()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO life.feed_status_live (source, last_event_at, events_today, expected_interval)
    VALUES ('mood', NOW(), 1, INTERVAL '24 hours')
    ON CONFLICT (source) DO UPDATE SET
        last_event_at = NOW(),
        events_today = CASE
            WHEN (life.feed_status_live.last_event_at AT TIME ZONE 'Asia/Dubai')::date = (NOW() AT TIME ZONE 'Asia/Dubai')::date
            THEN life.feed_status_live.events_today + 1
            ELSE 1
        END;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_mood_log_feed_status
    AFTER INSERT ON raw.mood_log
    FOR EACH ROW EXECUTE FUNCTION raw.update_mood_feed_status();

-- Daily mood summary view (for correlation analysis)
CREATE OR REPLACE VIEW raw.v_daily_mood_summary AS
SELECT
    date,
    ROUND(AVG(mood_score), 1) as avg_mood,
    ROUND(AVG(energy_score), 1) as avg_energy,
    COUNT(*) as log_count,
    MIN(mood_score) as min_mood,
    MAX(mood_score) as max_mood
FROM raw.mood_log
GROUP BY date;

-- ============================================
-- ADD TO DAILY_FACTS
-- ============================================

-- Add water and mood columns to daily_facts if not exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'life' AND table_name = 'daily_facts' AND column_name = 'water_ml') THEN
        ALTER TABLE life.daily_facts ADD COLUMN water_ml INT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'life' AND table_name = 'daily_facts' AND column_name = 'avg_mood') THEN
        ALTER TABLE life.daily_facts ADD COLUMN avg_mood NUMERIC(3,1);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'life' AND table_name = 'daily_facts' AND column_name = 'avg_energy') THEN
        ALTER TABLE life.daily_facts ADD COLUMN avg_energy NUMERIC(3,1);
    END IF;
END $$;

-- Grant permissions
GRANT SELECT, INSERT ON nutrition.water_log TO nexus;
GRANT USAGE, SELECT ON SEQUENCE nutrition.water_log_id_seq TO nexus;
GRANT SELECT, INSERT ON raw.mood_log TO nexus;
GRANT USAGE, SELECT ON SEQUENCE raw.mood_log_id_seq TO nexus;

COMMENT ON TABLE nutrition.water_log IS 'Water intake tracking from iOS app';
COMMENT ON TABLE raw.mood_log IS 'Mood and energy tracking from iOS app';
