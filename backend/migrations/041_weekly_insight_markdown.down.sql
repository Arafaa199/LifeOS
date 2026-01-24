-- Rollback Migration 041: Weekly Insight Markdown Report

DROP FUNCTION IF EXISTS insights.get_weekly_report_json(DATE);
DROP VIEW IF EXISTS insights.v_latest_weekly_report;
DROP FUNCTION IF EXISTS insights.store_weekly_report(DATE);
DROP FUNCTION IF EXISTS insights.generate_weekly_markdown(DATE);
