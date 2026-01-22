-- Migration 013 Rollback: Revert finance defaults and timestamp changes

BEGIN;

-- Revert currency default to USD
ALTER TABLE finance.transactions
  ALTER COLUMN currency SET DEFAULT 'USD';

-- Remove comments
COMMENT ON COLUMN finance.transactions.created_at IS NULL;
COMMENT ON COLUMN finance.transactions.transaction_at IS NULL;

-- Note: We do NOT revert the UPDATE that set NULL currencies to AED
-- That data change is permanent and should be manually reviewed if rollback is needed

COMMIT;
