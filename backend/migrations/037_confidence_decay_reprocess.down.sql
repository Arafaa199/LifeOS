-- Migration 037: Rollback Confidence Decay + Reprocess Pipeline
-- TASK-A2

DROP VIEW IF EXISTS ops.reprocess_queue_summary;
DROP FUNCTION IF EXISTS life.get_today_confidence_with_decay();
DROP FUNCTION IF EXISTS ops.reprocess_stale_days(INTEGER);
DROP VIEW IF EXISTS ops.reprocess_queue;
DROP VIEW IF EXISTS life.daily_confidence_with_decay;
