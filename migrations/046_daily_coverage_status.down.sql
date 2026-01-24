-- Rollback: 046_daily_coverage_status.down.sql

DROP VIEW IF EXISTS finance.coverage_summary;
DROP VIEW IF EXISTS finance.daily_coverage_status;
