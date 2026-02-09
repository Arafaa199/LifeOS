BEGIN;

-- Revert TASK-PLAN.5: Remove supplements feed status trigger

-- 1. Drop trigger
DROP TRIGGER IF EXISTS trg_supplement_log_feed_status ON health.supplement_log;

-- 2. Drop function
DROP FUNCTION IF EXISTS health.update_feed_status_supplements();

-- 3. Revert expected_interval to original 24h
UPDATE life.feed_status_live
SET expected_interval = '24 hours'::interval,
    last_event_at = NULL,
    events_today = 0
WHERE source = 'supplements';

-- Remove migration tracking
DELETE FROM ops.schema_migrations WHERE filename = '180_supplements_feed_trigger.up.sql';

COMMIT;
