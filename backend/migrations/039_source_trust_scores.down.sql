-- Migration: 039_source_trust_scores.down.sql
-- Rollback TASK-A3: Source Trust Scores

DROP FUNCTION IF EXISTS ops.update_source_trust;
DROP FUNCTION IF EXISTS life.get_today_confidence_weighted;
DROP VIEW IF EXISTS life.daily_confidence_weighted;
DROP FUNCTION IF EXISTS life.calculate_weighted_confidence;
DROP VIEW IF EXISTS ops.source_trust_status;
DROP TABLE IF EXISTS ops.source_trust;
