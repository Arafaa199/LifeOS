-- Migration 014 Rollback: Revert to partial unique index

BEGIN;

-- Drop full unique index
DROP INDEX IF EXISTS finance.idx_transactions_client_id;

-- Recreate partial unique index from migration 009
CREATE UNIQUE INDEX idx_transactions_client_id
  ON finance.transactions (client_id)
  WHERE client_id IS NOT NULL;

COMMIT;
