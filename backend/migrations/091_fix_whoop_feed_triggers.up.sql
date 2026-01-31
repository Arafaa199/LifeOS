-- Migration 091: Fix broken WHOOP feed_status triggers
--
-- Migration 090 created life.update_feed_status_sleep() and
-- life.update_feed_status_strain() that write to ops.feed_events,
-- which does not exist. The EXCEPTION WHEN OTHERS clause silently
-- swallows the error, so feed_status for sleep/strain never updates.
--
-- Fix: drop the broken functions (CASCADE drops their triggers too)
-- and recreate triggers using the correct life.update_feed_status()
-- pattern from migration 086.

-- Drop broken functions (and their triggers via CASCADE)
DROP FUNCTION IF EXISTS life.update_feed_status_sleep() CASCADE;
DROP FUNCTION IF EXISTS life.update_feed_status_strain() CASCADE;

-- Recreate triggers using the correct pattern
CREATE TRIGGER trg_feed_whoop_sleep
    AFTER INSERT OR UPDATE ON health.whoop_sleep
    FOR EACH ROW
    EXECUTE FUNCTION life.update_feed_status('whoop_sleep');

CREATE TRIGGER trg_feed_whoop_strain
    AFTER INSERT OR UPDATE ON health.whoop_strain
    FOR EACH ROW
    EXECUTE FUNCTION life.update_feed_status('whoop_strain');
