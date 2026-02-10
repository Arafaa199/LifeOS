-- Rollback migration 174

BEGIN;

-- Remove added accounts
DELETE FROM finance.accounts WHERE name IN ('Tabby Credit', 'Baseeta Credit');

-- Remove Feb 2026 budgets
DELETE FROM finance.budgets WHERE month = '2026-02-01';

-- Remove added recurring items
DELETE FROM finance.recurring_items WHERE name IN (
    'Chiller (LOGIC UTILS)', 'e& Mobile', 'Du Mobile+Internet',
    'ChatGPT Plus', 'Apple Subscriptions', 'Protein Powder',
    'Haircut (B27)', 'Car Wash', 'Petrol', 'Zain KSA', 'Rent Q1 2026'
);

-- Reactivate deactivated items
UPDATE finance.recurring_items SET is_active = true WHERE name IN (
    'Spotify', 'YouTube Premium', 'iCloud+', 'Car Insurance', 'Gym',
    'du Mobile', 'du Internet', 'Tabby Repayment'
);

-- Revert Claude Pro amount
UPDATE finance.recurring_items SET amount = 400, notes = NULL WHERE name = 'Claude Pro';

-- Revert DEWA amount
UPDATE finance.recurring_items SET amount = 500, notes = NULL WHERE name = 'DEWA';

-- Remove added installments
DELETE FROM finance.installments
WHERE merchant IN ('Samsung 49" Monitor (Amazon.ae)', 'Smart Home Bundle');

COMMIT;
