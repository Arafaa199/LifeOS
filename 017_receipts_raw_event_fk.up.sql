-- Migration 017: Add raw_event_id FK to existing receipts table
-- Links receipts to raw_events audit trail

ALTER TABLE finance.receipts
ADD COLUMN IF NOT EXISTS raw_event_id INTEGER REFERENCES finance.raw_events(id);

CREATE INDEX IF NOT EXISTS idx_receipts_raw_event_id ON finance.receipts(raw_event_id);

COMMENT ON COLUMN finance.receipts.raw_event_id IS 'FK to raw_events audit trail for traceability';
