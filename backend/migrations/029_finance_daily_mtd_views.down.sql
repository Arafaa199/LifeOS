-- Rollback: 029_finance_daily_mtd_views
-- Drop the finance daily and MTD views

DROP VIEW IF EXISTS facts.daily_totals;
DROP VIEW IF EXISTS facts.month_to_date_summary;
DROP VIEW IF EXISTS facts.daily_income;
DROP VIEW IF EXISTS facts.daily_spend;
