BEGIN;

-- TASK-PLAN.4: Fix "unknown" feed statuses for medications, screen_time, music
-- Problem: Three feed sources show "unknown" because no data has arrived yet.
-- - medications: trigger EXISTS (health.update_medications_feed_status) — just no data yet
-- - music: trigger EXISTS (life.update_music_feed_status) — already "ok"
-- - screen_time: NO trigger on the table (n8n updates feed_status inline in SQL,
--   but direct SQL inserts skip feed_status). Add the missing trigger.

-- 1. Create feed status trigger function for screen_time
CREATE OR REPLACE FUNCTION life.update_feed_status_screen_time()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO life.feed_status_live (source, last_event_at, events_today, expected_interval)
    VALUES ('screen_time', now(), 1, '48 hours'::interval)
    ON CONFLICT (source) DO UPDATE SET
        last_event_at = now(),
        events_today = life.feed_status_live.events_today + 1;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. Create trigger on life.screen_time_daily (INSERT OR UPDATE — webhook does ON CONFLICT DO UPDATE)
CREATE TRIGGER trg_screen_time_feed_status
    AFTER INSERT OR UPDATE ON life.screen_time_daily
    FOR EACH ROW
    EXECUTE FUNCTION life.update_feed_status_screen_time();

-- Track migration
INSERT INTO ops.schema_migrations (filename)
VALUES ('159_fix_unknown_feed_triggers.up.sql')
ON CONFLICT (filename) DO NOTHING;

COMMIT;
