-- Migration 069: Correction Layer for Messy Life Ready
-- Adds correction layer for auditability and control under messy conditions

-- 1. Add account_id to raw_events
ALTER TABLE finance.raw_events
ADD COLUMN IF NOT EXISTS account_id INTEGER REFERENCES finance.accounts(id);

-- 2. Add source column to transactions
ALTER TABLE finance.transactions
ADD COLUMN IF NOT EXISTS source VARCHAR(20) DEFAULT 'unknown';

-- Update existing transactions with source based on raw_data
UPDATE finance.transactions
SET source = 'sms'
WHERE raw_data IS NOT NULL AND source = 'unknown';

UPDATE finance.transactions
SET source = 'manual'
WHERE raw_data IS NULL AND source = 'unknown';

-- 3. Create transaction_corrections table
CREATE TABLE IF NOT EXISTS finance.transaction_corrections (
    id SERIAL PRIMARY KEY,
    transaction_id INTEGER NOT NULL REFERENCES finance.transactions(id) ON DELETE CASCADE,

    -- Corrected values (NULL = use original)
    corrected_amount NUMERIC(12,2),
    corrected_currency VARCHAR(3),
    corrected_category VARCHAR(50),
    corrected_merchant_name VARCHAR(200),
    corrected_transaction_at TIMESTAMPTZ,
    corrected_date DATE,
    corrected_account_id INTEGER REFERENCES finance.accounts(id),

    -- Audit fields
    notes TEXT,
    reason VARCHAR(100) NOT NULL,  -- 'wrong_amount', 'wrong_category', 'wrong_merchant', 'wrong_date', 'split', 'duplicate', 'other'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by VARCHAR(50) DEFAULT 'user',

    -- Active flag (only one active correction per transaction)
    is_active BOOLEAN DEFAULT TRUE
);

-- Index for fast lookup
CREATE INDEX IF NOT EXISTS idx_corrections_transaction
ON finance.transaction_corrections(transaction_id) WHERE is_active = TRUE;

-- Unique constraint: only one active correction per transaction
CREATE UNIQUE INDEX IF NOT EXISTS idx_corrections_unique_active
ON finance.transaction_corrections(transaction_id) WHERE is_active = TRUE;

-- 4. Create transactions_effective view
CREATE OR REPLACE VIEW finance.transactions_effective AS
SELECT
    t.id,
    t.external_id,
    t.source,

    -- Effective values (correction overrides original)
    COALESCE(c.corrected_amount, t.amount) AS amount,
    COALESCE(c.corrected_currency, t.currency) AS currency,
    COALESCE(c.corrected_category, t.category) AS category,
    COALESCE(c.corrected_merchant_name, t.merchant_name) AS merchant_name,
    COALESCE(c.corrected_date, t.date) AS date,
    COALESCE(c.corrected_transaction_at, t.transaction_at) AS transaction_at,
    COALESCE(c.corrected_account_id, t.account_id) AS account_id,

    -- Original values (always preserved)
    t.amount AS original_amount,
    t.currency AS original_currency,
    t.category AS original_category,
    t.merchant_name AS original_merchant_name,
    t.date AS original_date,
    t.transaction_at AS original_transaction_at,
    t.account_id AS original_account_id,

    -- Correction metadata
    c.id AS correction_id,
    c.reason AS correction_reason,
    c.notes AS correction_notes,
    c.created_at AS correction_created_at,
    CASE WHEN c.id IS NOT NULL THEN TRUE ELSE FALSE END AS is_corrected,

    -- Other transaction fields
    t.merchant_name_clean,
    t.subcategory,
    t.is_grocery,
    t.is_restaurant,
    t.is_food_related,
    t.store_name,
    t.receipt_processed,
    t.notes AS transaction_notes,
    t.tags,
    t.is_recurring,
    t.is_hidden,
    t.is_quarantined,
    t.quarantine_reason,
    t.raw_data,
    t.created_at,
    t.client_id,
    t.match_rule_id,
    t.match_reason,
    t.match_confidence

FROM finance.transactions t
LEFT JOIN finance.transaction_corrections c
    ON c.transaction_id = t.id AND c.is_active = TRUE;

-- 5. Correction functions

-- Function to create a correction (auto-deactivates previous)
CREATE OR REPLACE FUNCTION finance.create_correction(
    p_transaction_id INTEGER,
    p_amount NUMERIC DEFAULT NULL,
    p_currency VARCHAR DEFAULT NULL,
    p_category VARCHAR DEFAULT NULL,
    p_merchant_name VARCHAR DEFAULT NULL,
    p_date DATE DEFAULT NULL,
    p_transaction_at TIMESTAMPTZ DEFAULT NULL,
    p_account_id INTEGER DEFAULT NULL,
    p_reason VARCHAR DEFAULT 'manual_correction',
    p_notes TEXT DEFAULT NULL,
    p_created_by VARCHAR DEFAULT 'user'
)
RETURNS INTEGER AS $$
DECLARE
    v_correction_id INTEGER;
BEGIN
    -- Verify transaction exists
    IF NOT EXISTS (SELECT 1 FROM finance.transactions WHERE id = p_transaction_id) THEN
        RAISE EXCEPTION 'Transaction % not found', p_transaction_id;
    END IF;

    -- Deactivate any existing active correction
    UPDATE finance.transaction_corrections
    SET is_active = FALSE
    WHERE transaction_id = p_transaction_id AND is_active = TRUE;

    -- Create new correction
    INSERT INTO finance.transaction_corrections (
        transaction_id,
        corrected_amount,
        corrected_currency,
        corrected_category,
        corrected_merchant_name,
        corrected_date,
        corrected_transaction_at,
        corrected_account_id,
        reason,
        notes,
        created_by,
        is_active
    ) VALUES (
        p_transaction_id,
        p_amount,
        p_currency,
        p_category,
        p_merchant_name,
        p_date,
        p_transaction_at,
        p_account_id,
        p_reason,
        p_notes,
        p_created_by,
        TRUE
    )
    RETURNING id INTO v_correction_id;

    RETURN v_correction_id;
END;
$$ LANGUAGE plpgsql;

-- Function to deactivate a correction (reverts to original)
CREATE OR REPLACE FUNCTION finance.deactivate_correction(
    p_correction_id INTEGER
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE finance.transaction_corrections
    SET is_active = FALSE
    WHERE id = p_correction_id;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Function to link raw_event to transaction
CREATE OR REPLACE FUNCTION finance.link_raw_event(
    p_event_id INTEGER,
    p_transaction_id INTEGER
)
RETURNS BOOLEAN AS $$
BEGIN
    -- Verify event exists
    IF NOT EXISTS (SELECT 1 FROM finance.raw_events WHERE id = p_event_id) THEN
        RAISE EXCEPTION 'Raw event % not found', p_event_id;
    END IF;

    -- Verify transaction exists
    IF NOT EXISTS (SELECT 1 FROM finance.transactions WHERE id = p_transaction_id) THEN
        RAISE EXCEPTION 'Transaction % not found', p_transaction_id;
    END IF;

    UPDATE finance.raw_events
    SET
        related_transaction_id = p_transaction_id,
        resolution_status = 'linked',
        resolution_reason = 'manually_linked',
        resolved_at = NOW()
    WHERE id = p_event_id;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Function to ignore raw_event
CREATE OR REPLACE FUNCTION finance.ignore_raw_event(
    p_event_id INTEGER,
    p_reason TEXT
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE finance.raw_events
    SET
        resolution_status = 'ignored',
        resolution_reason = p_reason,
        resolved_at = NOW()
    WHERE id = p_event_id;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- 6. Reporting views

-- Coverage report by account
CREATE OR REPLACE VIEW finance.v_coverage_by_account AS
WITH raw_counts AS (
    SELECT
        COALESCE(account_id, 0) AS account_id,
        COUNT(*) AS raw_event_count,
        SUM(CASE WHEN resolution_status = 'linked' THEN 1 ELSE 0 END) AS linked_count,
        SUM(CASE WHEN resolution_status = 'ignored' THEN 1 ELSE 0 END) AS ignored_count,
        SUM(CASE WHEN resolution_status = 'pending' THEN 1 ELSE 0 END) AS pending_count,
        SUM(CASE WHEN resolution_status = 'failed' THEN 1 ELSE 0 END) AS failed_count
    FROM finance.raw_events
    GROUP BY 1
),
txn_counts AS (
    SELECT
        COALESCE(account_id, 0) AS account_id,
        COUNT(*) AS transaction_count,
        SUM(CASE WHEN source = 'sms' THEN 1 ELSE 0 END) AS sms_transactions,
        SUM(CASE WHEN source = 'manual' THEN 1 ELSE 0 END) AS manual_transactions
    FROM finance.transactions
    GROUP BY 1
)
SELECT
    COALESCE(a.name, 'Unknown') AS account_name,
    COALESCE(r.raw_event_count, 0) AS raw_events,
    COALESCE(r.linked_count, 0) AS linked,
    COALESCE(r.ignored_count, 0) AS ignored,
    COALESCE(r.pending_count, 0) AS unresolved,
    COALESCE(r.failed_count, 0) AS failed,
    COALESCE(t.transaction_count, 0) AS transactions,
    COALESCE(t.sms_transactions, 0) AS from_sms,
    COALESCE(t.manual_transactions, 0) AS manual
FROM (SELECT DISTINCT COALESCE(account_id, 0) AS account_id FROM finance.transactions
      UNION
      SELECT DISTINCT COALESCE(account_id, 0) FROM finance.raw_events) ids
LEFT JOIN finance.accounts a ON a.id = ids.account_id
LEFT JOIN raw_counts r ON r.account_id = ids.account_id
LEFT JOIN txn_counts t ON t.account_id = ids.account_id
ORDER BY COALESCE(t.transaction_count, 0) DESC;

-- Correction audit view
CREATE OR REPLACE VIEW finance.v_correction_audit AS
SELECT
    reason,
    COUNT(*) AS correction_count,
    COUNT(DISTINCT transaction_id) AS transactions_affected,
    MIN(created_at) AS first_correction,
    MAX(created_at) AS last_correction
FROM finance.transaction_corrections
GROUP BY reason
ORDER BY correction_count DESC;

-- Correction history for a transaction
CREATE OR REPLACE VIEW finance.v_correction_history AS
SELECT
    c.id AS correction_id,
    c.transaction_id,
    t.merchant_name AS original_merchant,
    c.corrected_merchant_name,
    t.amount AS original_amount,
    c.corrected_amount,
    t.category AS original_category,
    c.corrected_category,
    c.reason,
    c.notes,
    c.is_active,
    c.created_at,
    c.created_by
FROM finance.transaction_corrections c
JOIN finance.transactions t ON t.id = c.transaction_id
ORDER BY c.transaction_id, c.created_at DESC;
