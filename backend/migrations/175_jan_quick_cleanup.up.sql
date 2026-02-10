-- Migration 175: Quick cleanup for January 2026 transactions
-- 1. Consolidate "Grocery" → "Groceries"
-- 2. Categorize uncategorized salary as "Salary"

BEGIN;

-- Consolidate Grocery → Groceries
UPDATE finance.transactions
SET category = 'Groceries'
WHERE category = 'Grocery'
  AND transaction_at >= '2026-01-01'
  AND transaction_at < '2026-02-01';

-- Categorize uncategorized income as Salary (amounts > 10k are likely salary)
UPDATE finance.transactions
SET category = 'Salary'
WHERE category = 'Uncategorized'
  AND amount > 10000
  AND transaction_at >= '2026-01-01'
  AND transaction_at < '2026-02-01';

COMMIT;
