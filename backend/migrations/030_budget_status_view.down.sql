-- Migration: 030_budget_status_view (DOWN)
-- Purpose: Remove budget status views
-- TASK: M1.2 - Implement Budgets + Budget Status View

DROP VIEW IF EXISTS facts.budget_status_summary CASCADE;
DROP VIEW IF EXISTS facts.budget_status CASCADE;
