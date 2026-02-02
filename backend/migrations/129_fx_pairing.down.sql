-- Migration 129 rollback: Remove FX pairing columns
DROP INDEX IF EXISTS finance.idx_transactions_paired;
ALTER TABLE finance.transactions DROP COLUMN IF EXISTS pairing_role;
ALTER TABLE finance.transactions DROP COLUMN IF EXISTS paired_transaction_id;
