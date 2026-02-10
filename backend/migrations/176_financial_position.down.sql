-- Rollback migration 176

BEGIN;

DROP TRIGGER IF EXISTS trg_reconcile_payment ON finance.transactions;
DROP FUNCTION IF EXISTS finance.reconcile_payment();
DROP FUNCTION IF EXISTS finance.get_financial_position();
DROP VIEW IF EXISTS finance.v_upcoming_payments;
DROP TABLE IF EXISTS finance.account_balances;

-- Clear merchant patterns (optional, leaving them is harmless)
-- UPDATE finance.recurring_items SET merchant_pattern = NULL;

COMMIT;
