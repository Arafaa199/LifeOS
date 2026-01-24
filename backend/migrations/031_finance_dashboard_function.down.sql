-- Migration: 031_finance_dashboard_function (DOWN)
-- Purpose: Remove finance dashboard function
-- TASK: M1.3 - Add Finance Dashboard API Response
-- Created: 2026-01-24

DROP FUNCTION IF EXISTS finance.get_dashboard_payload();
