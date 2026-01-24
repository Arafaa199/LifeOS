-- Migration: 047_fix_client_id_constraint.up.sql
-- Purpose: Fix client_id unique constraint to allow ON CONFLICT
-- Date: 2026-01-25
--
-- Root cause: The partial index (WHERE client_id IS NOT NULL) didn't
-- support ON CONFLICT (client_id) DO NOTHING syntax.
-- Solution: Replace with a proper UNIQUE constraint.

-- Drop the partial index if it exists
DROP INDEX IF EXISTS finance.idx_transactions_client_id;

-- Add proper unique constraint (already done via CLI, this makes it idempotent)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'transactions_client_id_unique'
        AND conrelid = 'finance.transactions'::regclass
    ) THEN
        ALTER TABLE finance.transactions
        ADD CONSTRAINT transactions_client_id_unique UNIQUE (client_id);
    END IF;
END $$;

COMMENT ON CONSTRAINT transactions_client_id_unique ON finance.transactions IS
'Ensures client_id uniqueness for idempotent webhook ingestion. Required for ON CONFLICT syntax.';
