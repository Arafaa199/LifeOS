BEGIN;

-- Revert dashboard.get_payload() to v20 (remove habits_today)
-- Note: The full v20 function is restored from migration 186
-- For a clean rollback, re-run migration 186

-- Drop habit functions
DROP FUNCTION IF EXISTS life.get_habits_today();
DROP FUNCTION IF EXISTS life.get_habit_streaks(INT);

-- Drop tables (completions first due to FK)
DROP TABLE IF EXISTS life.habit_completions;
DROP TABLE IF EXISTS life.habits;

DELETE FROM ops.schema_migrations WHERE filename = '187_habits_system.up.sql';

COMMIT;
