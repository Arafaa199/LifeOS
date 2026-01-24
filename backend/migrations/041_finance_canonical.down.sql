-- Migration: 041_finance_canonical.down.sql
-- Rollback canonical finance layer

DROP FUNCTION IF EXISTS finance.get_canonical_daily_totals(INT);
DROP VIEW IF EXISTS finance.canonical_summary;
DROP VIEW IF EXISTS finance.daily_totals_aed;
DROP VIEW IF EXISTS finance.canonical_transactions;
