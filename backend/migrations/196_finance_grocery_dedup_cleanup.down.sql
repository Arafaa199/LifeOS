-- Rollback: 196_finance_grocery_dedup_cleanup
-- Reverts Groceries → Grocery, unquarantines dupes, restores original functions/views

BEGIN;

-- Revert category name
UPDATE finance.categories SET name = 'Grocery' WHERE id = 1 AND name = 'Groceries';
UPDATE finance.transactions SET category = 'Grocery' WHERE category = 'Groceries';
UPDATE finance.merchant_rules SET category = 'Grocery' WHERE category = 'Groceries';

-- Unquarantine the 4 dupe pairs
UPDATE finance.transactions
SET is_quarantined = false,
    notes = regexp_replace(notes, ' \[quarantined by migration 196:[^\]]*\]', '')
WHERE id IN (98920, 61416, 61418, 61417)
  AND is_quarantined = true;

-- Note: find_matching_transaction() and finalize_receipt() are NOT reverted
-- because the NULL-date fix and dedup logic are strictly improvements.
-- To fully revert, re-run migrations 012 and 088.

COMMIT;
