-- Migration 109 down: Remove monthly calendar summary view
DROP VIEW IF EXISTS life.v_monthly_calendar_summary;
