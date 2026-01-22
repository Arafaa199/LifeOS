-- Migration 013: Finance defaults and timestamp clarity
-- Purpose:
--   1. client_id unique index (ALREADY EXISTS from migration 009)
--   2. Change currency default from USD to AED
--   3. Document created_at as non-authoritative (transaction_at is authoritative)

BEGIN;

-- ============================================================================
-- 1. Verify client_id unique index exists (should exist from migration 009)
-- ============================================================================
-- Index: idx_transactions_client_id UNIQUE WHERE client_id IS NOT NULL
-- This ensures iOS app idempotency works correctly
-- No action needed - just verification

-- ============================================================================
-- 2. Change currency default to AED (Dubai Dirham)
-- ============================================================================
-- Most transactions are in AED, USD default was incorrect

ALTER TABLE finance.transactions
  ALTER COLUMN currency SET DEFAULT 'AED';

-- Update existing NULL currencies to AED (assume AED if not specified)
UPDATE finance.transactions
SET currency = 'AED'
WHERE currency IS NULL
   OR currency = '';

-- Update existing USD defaults to AED for recent transactions
-- (only if they were auto-assigned, not explicitly set)
-- Skip this - too risky to change existing data without explicit user approval
-- UPDATE finance.transactions
-- SET currency = 'AED'
-- WHERE currency = 'USD'
--   AND date >= '2024-01-01'
--   AND notes IS NULL;  -- assume auto-assigned if no notes

-- ============================================================================
-- 3. Document created_at vs transaction_at
-- ============================================================================
-- IMPORTANT: Two timestamp columns exist with different purposes:
--
-- created_at (timestamp without time zone, default now()):
--   - Non-authoritative, for record-keeping only
--   - Records when the row was inserted into Postgres
--   - NOT used for business logic, aggregations, or day boundaries
--   - Useful for debugging ingestion issues
--
-- transaction_at (timestamp with time zone):
--   - AUTHORITATIVE timestamp for business logic
--   - Records when the transaction actually occurred (in proper timezone)
--   - Used by finance.to_business_date() to determine which day a transaction belongs to
--   - Source of truth for all date-based queries
--
-- Why not migrate created_at to TIMESTAMPTZ?
--   - It's non-authoritative, so timezone precision doesn't matter
--   - Changing it would require downtime and doesn't add business value
--   - transaction_at already provides proper timezone-aware timestamps
--
-- Usage:
--   SELECT transaction_at AT TIME ZONE 'Asia/Dubai' AS local_time  -- CORRECT
--   SELECT created_at  -- AVOID in business logic

COMMENT ON COLUMN finance.transactions.created_at IS
  'Non-authoritative record insertion timestamp (for debugging only). Use transaction_at for all business logic.';

COMMENT ON COLUMN finance.transactions.transaction_at IS
  'AUTHORITATIVE transaction timestamp (timezone-aware). Use finance.to_business_date(transaction_at) for date aggregations.';

-- ============================================================================
-- Verification Queries (run after migration)
-- ============================================================================

-- 1. Verify client_id index exists
-- \d finance.transactions
-- Should show: "idx_transactions_client_id" UNIQUE, btree (client_id) WHERE client_id IS NOT NULL

-- 2. Verify currency default changed
-- SELECT column_default FROM information_schema.columns
-- WHERE table_schema = 'finance' AND table_name = 'transactions' AND column_name = 'currency';
-- Expected: 'AED'::character varying

-- 3. Verify no NULL currencies remain
-- SELECT COUNT(*) FROM finance.transactions WHERE currency IS NULL;
-- Expected: 0

-- 4. Check currency distribution
-- SELECT currency, COUNT(*) FROM finance.transactions GROUP BY currency ORDER BY COUNT(*) DESC;

-- 5. Verify comments exist
-- SELECT col_description('finance.transactions'::regclass,
--   (SELECT ordinal_position FROM information_schema.columns
--    WHERE table_schema = 'finance' AND table_name = 'transactions' AND column_name = 'created_at'));

COMMIT;
