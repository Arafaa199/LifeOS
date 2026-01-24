-- Migration: 027_correlation_views (rollback)
-- Removes correlation views

DROP VIEW IF EXISTS insights.productivity_recovery_correlation;
DROP VIEW IF EXISTS insights.screen_sleep_correlation;
DROP VIEW IF EXISTS insights.meetings_hrv_correlation;
DROP VIEW IF EXISTS insights.spending_by_recovery_level;
DROP VIEW IF EXISTS insights.spending_recovery_correlation;
DROP VIEW IF EXISTS insights.sleep_recovery_correlation;
DROP SCHEMA IF EXISTS insights;
