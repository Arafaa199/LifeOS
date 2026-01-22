-- Migration 015: Create finance.raw_events for audit trail
-- Purpose: Store raw webhook/SMS payloads for debugging and replay

BEGIN;

-- Create raw_events table for audit logging
CREATE TABLE finance.raw_events (
    id SERIAL PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL,  -- 'income_webhook', 'sms_import', etc.
    raw_payload JSONB NOT NULL,       -- Full raw payload from source
    client_id VARCHAR(36),             -- Optional client_id for correlation
    source_identifier VARCHAR(200),    -- SMS sender, IP address, etc.
    parsed_amount NUMERIC(10,2),      -- Server-parsed amount
    parsed_currency VARCHAR(3),        -- Server-parsed currency
    validation_status VARCHAR(20),     -- 'valid', 'invalid', 'duplicate'
    validation_errors TEXT[],          -- Array of validation errors
    related_transaction_id INTEGER,    -- FK to transactions if created
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT fk_related_transaction
        FOREIGN KEY (related_transaction_id)
        REFERENCES finance.transactions(id)
        ON DELETE SET NULL
);

-- Indexes for common queries
CREATE INDEX idx_raw_events_event_type ON finance.raw_events(event_type);
CREATE INDEX idx_raw_events_client_id ON finance.raw_events(client_id) WHERE client_id IS NOT NULL;
CREATE INDEX idx_raw_events_created_at ON finance.raw_events(created_at DESC);
CREATE INDEX idx_raw_events_validation_status ON finance.raw_events(validation_status);

-- Comments
COMMENT ON TABLE finance.raw_events IS
    'Audit trail for all incoming finance events (webhooks, SMS, etc.). Stores raw payloads for debugging and replay.';

COMMENT ON COLUMN finance.raw_events.event_type IS
    'Source type: income_webhook, expense_webhook, sms_import, manual_entry';

COMMENT ON COLUMN finance.raw_events.raw_payload IS
    'Complete raw JSON payload as received from source';

COMMENT ON COLUMN finance.raw_events.validation_status IS
    'Validation result: valid (processed), invalid (rejected), duplicate (idempotent skip)';

-- Verification query
-- SELECT event_type, validation_status, COUNT(*)
-- FROM finance.raw_events
-- WHERE created_at >= CURRENT_DATE
-- GROUP BY event_type, validation_status;

COMMIT;
