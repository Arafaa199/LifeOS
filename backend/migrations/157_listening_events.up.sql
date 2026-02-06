BEGIN;

-- Migration 157: Formalize life.listening_events table
-- Table was created manually for TASK-FEAT.24 (Apple Music Logging).
-- This migration ensures reproducibility on any fresh environment rebuild.

-- 1. Create table (IF NOT EXISTS for idempotency — already in prod)
CREATE TABLE IF NOT EXISTS life.listening_events (
    id              SERIAL PRIMARY KEY,
    session_id      UUID NOT NULL,
    track_title     TEXT NOT NULL,
    artist          TEXT,
    album           TEXT,
    duration_sec    INTEGER,
    apple_music_id  TEXT,
    started_at      TIMESTAMPTZ NOT NULL,
    ended_at        TIMESTAMPTZ,
    source          TEXT NOT NULL DEFAULT 'apple_music',
    raw_json        JSONB,
    created_at      TIMESTAMPTZ DEFAULT now()
);

-- 2. Unique constraint for idempotent inserts (n8n uses ON CONFLICT (session_id, started_at) DO NOTHING)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'listening_events_session_id_started_at_key'
    ) THEN
        ALTER TABLE life.listening_events
            ADD CONSTRAINT listening_events_session_id_started_at_key
            UNIQUE (session_id, started_at);
    END IF;
END $$;

-- 3. Indexes for query performance
CREATE INDEX IF NOT EXISTS idx_listening_events_session
    ON life.listening_events (session_id);

CREATE INDEX IF NOT EXISTS idx_listening_events_started
    ON life.listening_events (started_at DESC);

-- 4. Feed status trigger function
CREATE OR REPLACE FUNCTION life.update_music_feed_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE life.feed_status_live
    SET last_event_at = NOW(),
        events_today = events_today + 1
    WHERE source = 'music';
    RETURN NEW;
END;
$$;

-- 5. Attach trigger (drop first for idempotency)
DROP TRIGGER IF EXISTS trg_listening_events_feed ON life.listening_events;
CREATE TRIGGER trg_listening_events_feed
    AFTER INSERT ON life.listening_events
    FOR EACH ROW
    EXECUTE FUNCTION life.update_music_feed_status();

-- 6. Register in feed_status_live with 24h expected interval
INSERT INTO life.feed_status_live (source, last_event_at, events_today, expected_interval)
VALUES (
    'music',
    (SELECT MAX(created_at) FROM life.listening_events),
    (SELECT COUNT(*) FROM life.listening_events
     WHERE created_at::date = CURRENT_DATE),
    INTERVAL '24 hours'
)
ON CONFLICT (source) DO UPDATE SET
    expected_interval = INTERVAL '24 hours';

-- 7. Track migration
INSERT INTO ops.schema_migrations (filename, applied_at)
VALUES ('157_listening_events.up.sql', NOW())
ON CONFLICT DO NOTHING;

COMMIT;
