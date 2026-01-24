-- Migration 017 Rollback: Remove raw_event_id FK from receipts

DROP INDEX IF EXISTS finance.idx_receipts_raw_event_id;
ALTER TABLE finance.receipts DROP COLUMN IF EXISTS raw_event_id;
