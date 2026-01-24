-- Rollback: 047_fix_client_id_constraint.down.sql
-- Restore partial index (though not recommended)

ALTER TABLE finance.transactions DROP CONSTRAINT IF EXISTS transactions_client_id_unique;
CREATE UNIQUE INDEX idx_transactions_client_id ON finance.transactions (client_id) WHERE client_id IS NOT NULL;
