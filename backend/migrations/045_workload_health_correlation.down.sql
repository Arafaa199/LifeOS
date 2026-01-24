-- Migration: 045_workload_health_correlation.down.sql
-- Rollback: TASK-C3 - Workload vs Health Correlation

DROP VIEW IF EXISTS insights.workload_health_summary;
DROP VIEW IF EXISTS insights.workload_health_correlation_stats;
DROP VIEW IF EXISTS insights.workload_health_correlation;
DROP VIEW IF EXISTS insights.workload_daily;
