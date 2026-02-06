-- Rollback: 088_receipt_first_finalization
-- This migration replaces finance.finalize_receipt() with receipt-first logic.
-- Rollback would require restoring v2 function and reversing data fixes.

-- Revert data fixes (safe to run multiple times)
UPDATE finance.transactions
SET source = NULL, receipt_processed = false
WHERE notes LIKE 'Auto-created from receipt%'
  AND source = 'receipt';

-- Note: Function rollback omitted - would need v2 function body
SELECT 'Migration 088 partially rolled back - function not reverted';
