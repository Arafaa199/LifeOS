-- Migration 038: Finance Budget Engine View (ROLLBACK)
-- Drops the budget engine views

DROP VIEW IF EXISTS finance.budget_engine_summary CASCADE;
DROP VIEW IF EXISTS finance.budget_engine CASCADE;
