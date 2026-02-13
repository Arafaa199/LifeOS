BEGIN;

-- Revert TASK-PLAN.1: Remove habits feed status tracking

-- 1. Drop trigger
DROP TRIGGER IF EXISTS trg_habit_completions_feed_status ON life.habit_completions;

-- 2. Drop function
DROP FUNCTION IF EXISTS life.update_feed_status_habits();

-- 3. Remove feed status entry
DELETE FROM life.feed_status_live WHERE source = 'habits';

-- Remove migration tracking
DELETE FROM ops.schema_migrations WHERE filename = '192_habits_feed_status.up.sql';

COMMIT;
