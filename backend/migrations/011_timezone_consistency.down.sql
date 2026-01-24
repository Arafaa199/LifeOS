-- Rollback Migration 011: Timezone Consistency

-- Drop trigger
DROP TRIGGER IF EXISTS set_transaction_at_trigger ON finance.transactions;
DROP FUNCTION IF EXISTS finance.set_transaction_at();

-- Drop index
DROP INDEX IF EXISTS finance.idx_transactions_transaction_at;

-- Drop functions
DROP FUNCTION IF EXISTS finance.current_business_date();
DROP FUNCTION IF EXISTS finance.to_business_date(TIMESTAMPTZ);

-- Remove transaction_at column
ALTER TABLE finance.transactions DROP COLUMN IF EXISTS transaction_at;

-- Convert created_at back to timestamp without time zone
-- This is safe - data remains unchanged, just loses explicit TZ
ALTER TABLE finance.transactions
ALTER COLUMN created_at TYPE TIMESTAMP WITHOUT TIME ZONE;

-- Remove comments
COMMENT ON COLUMN finance.transactions.created_at IS NULL;
COMMENT ON COLUMN finance.transactions.date IS NULL;
