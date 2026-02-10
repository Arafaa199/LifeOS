-- Rollback migration 175
-- Note: This is a best-effort rollback - original categories may not be perfectly restored

BEGIN;

-- Revert Salary back to Uncategorized for Jan income > 10k
UPDATE finance.transactions
SET category = 'Uncategorized'
WHERE category = 'Salary'
  AND amount > 10000
  AND transaction_at >= '2026-01-01'
  AND transaction_at < '2026-02-01';

-- Note: Cannot reliably revert Groceries → Grocery as we don't know which were originally "Grocery"

COMMIT;
