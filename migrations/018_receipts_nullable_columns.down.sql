-- Migration: 018_receipts_nullable_columns (rollback)
-- Note: Rollback may fail if NULL values exist in these columns

-- Restore NOT NULL constraints
ALTER TABLE finance.receipts
    ALTER COLUMN gmail_message_id SET NOT NULL,
    ALTER COLUMN email_received_at SET NOT NULL,
    ALTER COLUMN vendor SET NOT NULL;

-- Remove default
ALTER TABLE finance.receipts
    ALTER COLUMN vendor DROP DEFAULT;

-- Restore original index
DROP INDEX IF EXISTS finance.idx_receipts_gmail_message_id;
CREATE INDEX idx_receipts_gmail_message_id ON finance.receipts(gmail_message_id);
