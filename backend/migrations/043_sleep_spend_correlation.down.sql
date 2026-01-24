-- TASK-C1: Rollback sleep vs spending correlation views

DROP VIEW IF EXISTS insights.sleep_spend_summary CASCADE;
DROP VIEW IF EXISTS insights.sleep_spend_same_day CASCADE;
DROP VIEW IF EXISTS insights.sleep_spend_correlation CASCADE;
DROP VIEW IF EXISTS insights.sleep_spend_daily CASCADE;
