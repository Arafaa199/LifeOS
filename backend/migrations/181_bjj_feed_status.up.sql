BEGIN;

-- TASK-PLAN.6: Add BJJ feed status tracking
-- Problem: BJJ sessions (health.bjj_sessions, migration 178) have no feed status entry.
-- Pipeline Health view shows all domains except BJJ.
-- Fix: Insert feed entry + trigger on health.bjj_sessions (same pattern as migration 180).

-- 1. Insert bjj source into feed_status_live (7-day interval — weekly training frequency)
INSERT INTO life.feed_status_live (source, expected_interval, events_today)
VALUES ('bjj', '7 days'::interval, 0)
ON CONFLICT (source) DO NOTHING;

-- 2. Create feed status trigger function for BJJ
CREATE OR REPLACE FUNCTION health.update_feed_status_bjj()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO life.feed_status_live (source, last_event_at, events_today, expected_interval)
    VALUES ('bjj', now(), 1, '7 days'::interval)
    ON CONFLICT (source) DO UPDATE SET
        last_event_at = now(),
        events_today = life.feed_status_live.events_today + 1;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Create trigger on health.bjj_sessions (INSERT OR UPDATE — webhook may upsert)
CREATE TRIGGER trg_bjj_sessions_feed_status
    AFTER INSERT OR UPDATE ON health.bjj_sessions
    FOR EACH ROW
    EXECUTE FUNCTION health.update_feed_status_bjj();

-- Track migration
INSERT INTO ops.schema_migrations (filename)
VALUES ('181_bjj_feed_status.up.sql')
ON CONFLICT (filename) DO NOTHING;

COMMIT;
