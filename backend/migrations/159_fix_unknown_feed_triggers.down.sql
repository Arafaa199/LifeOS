BEGIN;

-- Revert TASK-PLAN.4: Remove screen_time feed status trigger
DROP TRIGGER IF EXISTS trg_screen_time_feed_status ON life.screen_time_daily;
DROP FUNCTION IF EXISTS life.update_feed_status_screen_time();

DELETE FROM ops.schema_migrations WHERE filename = '159_fix_unknown_feed_triggers.up.sql';

COMMIT;
