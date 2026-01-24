-- Migration: 044_screen_sleep_aggregation (down)
-- TASK-C2: Screen Time vs Sleep Quality Correlation

DROP VIEW IF EXISTS insights.tv_sleep_summary;
DROP VIEW IF EXISTS insights.tv_sleep_correlation_stats;
DROP VIEW IF EXISTS insights.tv_sleep_aggregation;
DROP VIEW IF EXISTS insights.tv_sleep_daily;
