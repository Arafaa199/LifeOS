BEGIN;

-- Migration 194: Fix Mood Feed Status Entry
-- Ensures mood row exists in feed_status_live and trigger fires on INSERT OR UPDATE
-- (Migration 162 created both row and trigger, but trigger was INSERT-only)

-- 1. Ensure mood entry exists in feed_status_live (safety net)
INSERT INTO life.feed_status_live (source, last_event_at, events_today, expected_interval)
VALUES ('mood', NULL, 0, INTERVAL '24 hours')
ON CONFLICT (source) DO NOTHING;

-- 2. Recreate trigger to fire on INSERT OR UPDATE (was INSERT only)
DROP TRIGGER IF EXISTS trg_mood_log_feed_status ON raw.mood_log;

CREATE TRIGGER trg_mood_log_feed_status
    AFTER INSERT OR UPDATE ON raw.mood_log
    FOR EACH ROW EXECUTE FUNCTION raw.update_mood_feed_status();

INSERT INTO ops.schema_migrations (filename) VALUES ('194_fix_mood_feed_entry.up.sql')
ON CONFLICT DO NOTHING;

COMMIT;
