-- Rollback migration 018

DROP TABLE IF EXISTS finance.receipt_templates;
DROP INDEX IF EXISTS finance.idx_receipts_template_hash;

ALTER TABLE finance.receipts
DROP COLUMN IF EXISTS template_hash,
DROP COLUMN IF EXISTS parse_version;
