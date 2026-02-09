BEGIN;

-- Revert TASK-PLAN.6: Remove BJJ feed status tracking

-- 1. Drop trigger
DROP TRIGGER IF EXISTS trg_bjj_sessions_feed_status ON health.bjj_sessions;

-- 2. Drop function
DROP FUNCTION IF EXISTS health.update_feed_status_bjj();

-- 3. Remove feed status entry (didn't exist before this migration)
DELETE FROM life.feed_status_live WHERE source = 'bjj';

-- Remove migration tracking
DELETE FROM ops.schema_migrations WHERE filename = '181_bjj_feed_status.up.sql';

COMMIT;
