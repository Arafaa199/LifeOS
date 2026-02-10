BEGIN;

-- Revert to v2 explain_today (migration 182)
-- The full v2 function would need to be restored from 182_smart_briefing.up.sql

DELETE FROM ops.schema_migrations WHERE filename = '188_habits_explain_today.up.sql';

COMMIT;
