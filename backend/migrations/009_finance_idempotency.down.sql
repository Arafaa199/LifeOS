-- Rollback migration 009: Remove client_id idempotency
BEGIN;

DROP INDEX IF EXISTS finance.idx_transactions_client_id;
ALTER TABLE finance.transactions DROP COLUMN IF EXISTS client_id;

COMMIT;
