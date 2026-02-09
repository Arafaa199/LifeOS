BEGIN;

-- TASK-PLAN.5: Add supplements feed status trigger
-- Problem: supplements feed shows "unknown" permanently because no trigger
-- updates life.feed_status_live when doses are logged via health.log_supplement_dose().
-- Fix: Add AFTER INSERT OR UPDATE trigger on health.supplement_log (same pattern as migration 159).

-- 1. Update expected_interval to 48h (supplements are daily but user may skip days)
UPDATE life.feed_status_live
SET expected_interval = '48 hours'::interval
WHERE source = 'supplements';

-- 2. Create feed status trigger function for supplements
CREATE OR REPLACE FUNCTION health.update_feed_status_supplements()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO life.feed_status_live (source, last_event_at, events_today, expected_interval)
    VALUES ('supplements', now(), 1, '48 hours'::interval)
    ON CONFLICT (source) DO UPDATE SET
        last_event_at = now(),
        events_today = life.feed_status_live.events_today + 1;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Create trigger on health.supplement_log (INSERT OR UPDATE — webhook may upsert)
CREATE TRIGGER trg_supplement_log_feed_status
    AFTER INSERT OR UPDATE ON health.supplement_log
    FOR EACH ROW
    EXECUTE FUNCTION health.update_feed_status_supplements();

-- Track migration
INSERT INTO ops.schema_migrations (filename)
VALUES ('180_supplements_feed_trigger.up.sql')
ON CONFLICT (filename) DO NOTHING;

COMMIT;
