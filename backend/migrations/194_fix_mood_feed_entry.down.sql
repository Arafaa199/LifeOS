BEGIN;

-- Revert to INSERT-only trigger (original migration 162 behavior)
DROP TRIGGER IF EXISTS trg_mood_log_feed_status ON raw.mood_log;

CREATE TRIGGER trg_mood_log_feed_status
    AFTER INSERT ON raw.mood_log
    FOR EACH ROW EXECUTE FUNCTION raw.update_mood_feed_status();

DELETE FROM ops.schema_migrations WHERE filename = '194_fix_mood_feed_entry.up.sql';

COMMIT;
