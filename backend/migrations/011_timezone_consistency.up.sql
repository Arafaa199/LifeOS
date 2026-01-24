-- Migration 011: Timezone Consistency for Finance Data
-- Ensures precise transaction timing with TIMESTAMPTZ and defines business date derivation
--
-- NOTE: created_at remains as timestamp without time zone due to many view dependencies.
-- The new transaction_at column uses TIMESTAMPTZ for proper timezone handling.
-- Future migrations can convert created_at after refactoring dependent views.

-- 1. Add transaction_at for precise transaction timing with timezone
ALTER TABLE finance.transactions
ADD COLUMN IF NOT EXISTS transaction_at TIMESTAMPTZ;

-- 2. Backfill transaction_at from existing data
-- For SMS imports: date is the actual transaction date, use midnight Dubai time
-- For manual entries: use created_at interpreted as UTC
UPDATE finance.transactions
SET transaction_at = CASE
    -- If date differs from created_at date, it's likely an SMS import
    -- Use the date at midnight Dubai time
    WHEN date != (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Dubai')::date
    THEN (date::timestamp AT TIME ZONE 'Asia/Dubai')
    -- Otherwise interpret created_at as UTC (which it is, since DB timezone is UTC)
    ELSE created_at AT TIME ZONE 'UTC'
END
WHERE transaction_at IS NULL;

-- 3. Create function to derive business date from timestamp
-- Business date is the date in Asia/Dubai timezone (UTC+4)
-- This is the single source of truth for date derivation
CREATE OR REPLACE FUNCTION finance.to_business_date(ts TIMESTAMPTZ)
RETURNS DATE AS $$
BEGIN
    RETURN (ts AT TIME ZONE 'Asia/Dubai')::date;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 4. Create function to get current business date
CREATE OR REPLACE FUNCTION finance.current_business_date()
RETURNS DATE AS $$
BEGIN
    RETURN finance.to_business_date(NOW());
END;
$$ LANGUAGE plpgsql STABLE;

-- 5. Add documentation comments
COMMENT ON COLUMN finance.transactions.transaction_at IS
    'Transaction occurrence time (TIMESTAMPTZ). When the transaction actually happened. '
    'Business date derived via: finance.to_business_date(transaction_at)';
COMMENT ON COLUMN finance.transactions.date IS
    'Business date (DATE). For historical data, from bank SMS. '
    'For new data, should match finance.to_business_date(transaction_at).';
COMMENT ON FUNCTION finance.to_business_date(TIMESTAMPTZ) IS
    'Converts a TIMESTAMPTZ to business date using Asia/Dubai timezone (UTC+4). '
    'This is the single source of truth for date derivation.';

-- 6. Create index on transaction_at for time-based queries
CREATE INDEX IF NOT EXISTS idx_transactions_transaction_at
ON finance.transactions(transaction_at DESC);

-- 7. Add trigger to auto-set transaction_at on insert if not provided
CREATE OR REPLACE FUNCTION finance.set_transaction_at()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.transaction_at IS NULL THEN
        NEW.transaction_at := NOW();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_transaction_at_trigger ON finance.transactions;
CREATE TRIGGER set_transaction_at_trigger
    BEFORE INSERT ON finance.transactions
    FOR EACH ROW
    EXECUTE FUNCTION finance.set_transaction_at();
