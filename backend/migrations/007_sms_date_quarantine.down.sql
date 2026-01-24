-- Rollback: 007_sms_date_quarantine
-- Purpose: Remove quarantine system for transactions with suspect dates
-- Date: 2026-01-21

BEGIN;

-- Remove function
DROP FUNCTION IF EXISTS finance.quarantine_suspect_dates();

-- Remove quarantine log table
DROP TABLE IF EXISTS ops.quarantine_log;

-- Remove feature flag
DELETE FROM ops.feature_flags WHERE flag_name = 'sms_quarantine_enabled';

-- Remove index
DROP INDEX IF EXISTS finance.idx_transactions_quarantined;

-- Remove columns from finance.transactions
-- Note: This will lose quarantine data - use with caution
ALTER TABLE finance.transactions DROP COLUMN IF EXISTS quarantine_reason;
ALTER TABLE finance.transactions DROP COLUMN IF EXISTS is_quarantined;

COMMIT;
