-- Migration: 018_receipts_nullable_columns
-- Purpose: Allow nullable columns for raw receipt ingest (not all metadata available initially)
-- Created: 2026-01-22

-- Make email metadata columns nullable for raw ingest scenarios
ALTER TABLE finance.receipts
    ALTER COLUMN gmail_message_id DROP NOT NULL,
    ALTER COLUMN email_received_at DROP NOT NULL,
    ALTER COLUMN vendor DROP NOT NULL;

-- Add default for vendor when NULL
ALTER TABLE finance.receipts
    ALTER COLUMN vendor SET DEFAULT 'unknown';

-- Update index to handle NULL gmail_message_id
DROP INDEX IF EXISTS finance.idx_receipts_gmail_message_id;
CREATE INDEX idx_receipts_gmail_message_id ON finance.receipts(gmail_message_id)
    WHERE gmail_message_id IS NOT NULL;

COMMENT ON COLUMN finance.receipts.gmail_message_id IS 'Gmail message ID (NULL for non-email sources)';
COMMENT ON COLUMN finance.receipts.email_received_at IS 'Email timestamp (NULL for non-email sources)';
COMMENT ON COLUMN finance.receipts.vendor IS 'Vendor identifier (defaults to unknown for raw ingest)';
