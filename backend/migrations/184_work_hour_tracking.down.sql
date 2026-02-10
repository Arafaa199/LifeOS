BEGIN;

DROP FUNCTION IF EXISTS life.get_work_summary(DATE);
DROP VIEW IF EXISTS life.v_work_sessions;

-- Note: dashboard.get_payload and life.explain_today are replaced in-place
-- and would need the previous migration's version to fully rollback.
-- The work_summary key will simply return NULL if the function is dropped.

DELETE FROM ops.schema_migrations WHERE filename = '184_work_hour_tracking.up.sql';

COMMIT;
