-- Rollback Migration 032: Remove ops.pipeline_health view
DROP VIEW IF EXISTS ops.pipeline_health;
