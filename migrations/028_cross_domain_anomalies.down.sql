-- Migration: 028_cross_domain_anomalies (rollback)
-- Removes anomaly detection views

DROP VIEW IF EXISTS insights.pattern_detector;
DROP VIEW IF EXISTS insights.cross_domain_alerts;
DROP VIEW IF EXISTS insights.daily_anomalies;
