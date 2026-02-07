-- Migration: 163_installments
-- Description: BNPL installment tracking for Tabby, Tamara, Postpay

CREATE TABLE IF NOT EXISTS finance.installments (
    id SERIAL PRIMARY KEY,
    source TEXT NOT NULL CHECK (source IN ('tabby', 'tamara', 'postpay', 'other')),
    merchant TEXT NOT NULL,
    total_amount NUMERIC(12,2) NOT NULL,
    currency TEXT NOT NULL DEFAULT 'AED',
    installments_total INT NOT NULL CHECK (installments_total > 0),
    installments_paid INT NOT NULL DEFAULT 0 CHECK (installments_paid >= 0),
    installment_amount NUMERIC(12,2) NOT NULL,
    purchase_date DATE,
    next_due_date DATE,
    final_due_date DATE,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'cancelled', 'overdue')),
    original_transaction_id INT REFERENCES finance.transactions(id),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_installments_status ON finance.installments (status);
CREATE INDEX idx_installments_next_due ON finance.installments (next_due_date) WHERE status = 'active';
CREATE INDEX idx_installments_source ON finance.installments (source);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION finance.update_installments_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_installments_updated
    BEFORE UPDATE ON finance.installments
    FOR EACH ROW EXECUTE FUNCTION finance.update_installments_timestamp();

-- View for active installments with computed fields
CREATE OR REPLACE VIEW finance.v_active_installments AS
SELECT
    i.id,
    i.source,
    i.merchant,
    i.total_amount,
    i.currency,
    i.installments_total,
    i.installments_paid,
    i.installment_amount,
    i.purchase_date,
    i.next_due_date,
    i.final_due_date,
    i.status,
    -- Computed fields
    (i.installments_total - i.installments_paid) AS remaining_payments,
    ((i.installments_total - i.installments_paid) * i.installment_amount)::NUMERIC(12,2) AS remaining_amount,
    CASE
        WHEN i.next_due_date IS NOT NULL AND i.next_due_date < (NOW() AT TIME ZONE 'Asia/Dubai')::date
        THEN true
        ELSE false
    END AS is_overdue,
    CASE
        WHEN i.next_due_date IS NOT NULL
             AND i.next_due_date >= (NOW() AT TIME ZONE 'Asia/Dubai')::date
             AND i.next_due_date <= ((NOW() AT TIME ZONE 'Asia/Dubai')::date + INTERVAL '7 days')
        THEN true
        ELSE false
    END AS is_due_soon
FROM finance.installments i
WHERE i.status = 'active'
ORDER BY i.next_due_date ASC NULLS LAST;

-- Feed status for monitoring
INSERT INTO life.feed_status_live (source, last_event_at, events_today, expected_interval)
VALUES ('installments', NULL, 0, INTERVAL '7 days')
ON CONFLICT (source) DO NOTHING;

-- Trigger to update feed_status on writes
CREATE OR REPLACE FUNCTION finance.update_installments_feed_status()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE life.feed_status_live
    SET
        last_event_at = NOW(),
        events_today = COALESCE(events_today, 0) + 1
    WHERE source = 'installments';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_installments_feed_status
    AFTER INSERT OR UPDATE ON finance.installments
    FOR EACH ROW EXECUTE FUNCTION finance.update_installments_feed_status();

-- Function to mark payment made on an installment
CREATE OR REPLACE FUNCTION finance.record_installment_payment(p_installment_id INT)
RETURNS finance.installments AS $$
DECLARE
    result finance.installments;
BEGIN
    UPDATE finance.installments
    SET
        installments_paid = installments_paid + 1,
        next_due_date = CASE
            WHEN installments_paid + 1 >= installments_total THEN NULL
            ELSE next_due_date + INTERVAL '1 month'
        END,
        status = CASE
            WHEN installments_paid + 1 >= installments_total THEN 'completed'
            ELSE status
        END
    WHERE id = p_installment_id
    RETURNING * INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql;

GRANT SELECT, INSERT, UPDATE ON finance.installments TO nexus;
GRANT USAGE, SELECT ON SEQUENCE finance.installments_id_seq TO nexus;
GRANT SELECT ON finance.v_active_installments TO nexus;
GRANT EXECUTE ON FUNCTION finance.record_installment_payment(INT) TO nexus;
