-- Rollback Migration 123: Remove rebuild function and audit table

DROP FUNCTION IF EXISTS life.rebuild_daily_facts(DATE, DATE, TEXT);
DROP TABLE IF EXISTS ops.rebuild_runs;
