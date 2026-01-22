-- Migration 014: Convert client_id to full unique index
-- Issue: Partial unique index (WHERE client_id IS NOT NULL) doesn't work with ON CONFLICT
-- Solution: Drop partial index, create full unique index (NULL values still allowed)

BEGIN;

-- Drop partial unique index from migration 009
DROP INDEX IF EXISTS finance.idx_transactions_client_id;

-- Create full unique index
-- Note: Multiple NULL values are allowed in unique indexes
CREATE UNIQUE INDEX idx_transactions_client_id
  ON finance.transactions (client_id);

COMMENT ON INDEX finance.idx_transactions_client_id IS
  'Full unique index on client_id for ON CONFLICT support. NULL values are allowed (unique constraint only applies to non-NULL values).';

COMMIT;
