-- Migration 139 Rollback: Remove fasting tracker

BEGIN;

DROP FUNCTION IF EXISTS health.get_fasting_status();
DROP FUNCTION IF EXISTS health.start_fast();
DROP FUNCTION IF EXISTS health.break_fast();
DROP TABLE IF EXISTS health.fasting_sessions;

-- Note: dashboard.get_payload would need to be restored to previous version
-- This is a simplified rollback - full restoration would require the v8 function

COMMIT;
