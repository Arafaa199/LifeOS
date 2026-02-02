-- Migration 129: FX Pairing columns for duplicate SMS detection
-- When a sender (e.g. TASHEEL FIN) sends both a notification (merchant currency)
-- and a confirmed (billed currency) SMS for the same purchase, we pair them
-- so the notification is flagged as fx_metadata and excluded from aggregations.

ALTER TABLE finance.transactions
  ADD COLUMN IF NOT EXISTS paired_transaction_id INTEGER REFERENCES finance.transactions(id),
  ADD COLUMN IF NOT EXISTS pairing_role VARCHAR(30);

COMMENT ON COLUMN finance.transactions.paired_transaction_id IS 'Links fx_metadata row to its primary (ledger) transaction';
COMMENT ON COLUMN finance.transactions.pairing_role IS 'primary = ledger tx, fx_metadata = informational duplicate, NULL = unpaired';

CREATE INDEX IF NOT EXISTS idx_transactions_paired
  ON finance.transactions(paired_transaction_id)
  WHERE paired_transaction_id IS NOT NULL;
