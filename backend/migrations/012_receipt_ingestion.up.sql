-- Migration: 012_receipt_ingestion
-- Purpose: Receipt ingestion system for Carrefour UAE (and future vendors)
-- Created: 2026-01-22

-- ============================================================================
-- RAW RECEIPT STORAGE
-- ============================================================================

-- Store raw receipt metadata from Gmail
CREATE TABLE IF NOT EXISTS finance.receipts (
    id SERIAL PRIMARY KEY,

    -- Gmail source (multiple PDFs can come from same message)
    gmail_message_id VARCHAR(100) NOT NULL,
    gmail_thread_id VARCHAR(100),
    gmail_label VARCHAR(100),
    email_from VARCHAR(255),
    email_subject VARCHAR(500),
    email_received_at TIMESTAMPTZ NOT NULL,

    -- PDF storage
    pdf_hash VARCHAR(64) UNIQUE NOT NULL,  -- SHA256 of PDF content
    pdf_filename VARCHAR(255),
    pdf_size_bytes INTEGER,
    pdf_storage_path VARCHAR(500),  -- Path relative to storage root

    -- Vendor identification
    vendor VARCHAR(50) NOT NULL,  -- 'carrefour_uae', 'lulu', etc.

    -- Receipt metadata (extracted from PDF)
    invoice_number VARCHAR(100),
    store_name VARCHAR(200),
    store_address TEXT,
    receipt_date DATE,
    receipt_time TIME,
    receipt_datetime TIMESTAMPTZ,

    -- Totals
    subtotal NUMERIC(10,2),
    vat_amount NUMERIC(10,2),
    total_amount NUMERIC(10,2),
    currency VARCHAR(3) DEFAULT 'AED',

    -- Processing status
    parse_status VARCHAR(20) DEFAULT 'pending' CHECK (parse_status IN ('pending', 'success', 'failed', 'partial')),
    parse_error TEXT,
    parsed_at TIMESTAMPTZ,

    -- Transaction linkage
    linked_transaction_id INTEGER REFERENCES finance.transactions(id),
    link_confidence NUMERIC(3,2),  -- 0.00 to 1.00
    link_method VARCHAR(50),  -- 'exact_match', 'fuzzy_date_amount', 'manual'
    linked_at TIMESTAMPTZ,

    -- Audit
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for finding unlinked receipts
CREATE INDEX idx_receipts_unlinked ON finance.receipts(receipt_date)
    WHERE linked_transaction_id IS NULL AND parse_status = 'success';

-- Index for vendor-specific queries
CREATE INDEX idx_receipts_vendor ON finance.receipts(vendor, receipt_date DESC);

-- Index for processing queue
CREATE INDEX idx_receipts_pending ON finance.receipts(created_at)
    WHERE parse_status = 'pending';

-- ============================================================================
-- RECEIPT LINE ITEMS
-- ============================================================================

CREATE TABLE IF NOT EXISTS finance.receipt_items (
    id SERIAL PRIMARY KEY,
    receipt_id INTEGER NOT NULL REFERENCES finance.receipts(id) ON DELETE CASCADE,

    -- Line item data
    line_number INTEGER,  -- Position on receipt
    item_code VARCHAR(50),  -- Barcode/SKU if available
    item_description VARCHAR(500) NOT NULL,
    item_description_clean VARCHAR(500),  -- Normalized name

    -- Quantity and price
    quantity NUMERIC(10,3) DEFAULT 1,
    unit VARCHAR(20),  -- 'each', 'kg', 'g', 'l', etc.
    unit_price NUMERIC(10,2),
    line_total NUMERIC(10,2) NOT NULL,

    -- Discount handling
    discount_amount NUMERIC(10,2) DEFAULT 0,
    original_price NUMERIC(10,2),
    is_promotional BOOLEAN DEFAULT FALSE,
    promotion_description VARCHAR(200),

    -- Categorization (for future use, not auto-populated)
    category VARCHAR(50),
    subcategory VARCHAR(50),

    -- Audit
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for item lookups
CREATE INDEX idx_receipt_items_receipt ON finance.receipt_items(receipt_id);
CREATE INDEX idx_receipt_items_description ON finance.receipt_items(item_description_clean);

-- ============================================================================
-- RAW TEXT STORAGE (for debugging/re-parsing)
-- ============================================================================

CREATE TABLE IF NOT EXISTS finance.receipt_raw_text (
    receipt_id INTEGER PRIMARY KEY REFERENCES finance.receipts(id) ON DELETE CASCADE,
    raw_text TEXT NOT NULL,
    extraction_method VARCHAR(50) DEFAULT 'pdftotext',  -- 'pdftotext', 'pypdf', etc.
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- VENDOR PARSERS REGISTRY
-- ============================================================================

CREATE TABLE IF NOT EXISTS finance.receipt_parsers (
    vendor VARCHAR(50) PRIMARY KEY,
    parser_version VARCHAR(20) NOT NULL,
    vendor_patterns JSONB NOT NULL,  -- Regex patterns to identify this vendor
    is_active BOOLEAN DEFAULT TRUE,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed Carrefour UAE parser config
INSERT INTO finance.receipt_parsers (vendor, parser_version, vendor_patterns, notes)
VALUES (
    'carrefour_uae',
    '1.0.0',
    '{
        "email_from": ["noreply@carrefouruae.com", "carrefour"],
        "email_subject": ["receipt", "invoice", "order"],
        "pdf_patterns": ["CARREFOUR", "MAF RETAIL", "majid al futtaim"]
    }',
    'Carrefour UAE grocery receipts'
) ON CONFLICT (vendor) DO UPDATE SET
    parser_version = EXCLUDED.parser_version,
    vendor_patterns = EXCLUDED.vendor_patterns,
    updated_at = NOW();

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to link receipt to transaction
CREATE OR REPLACE FUNCTION finance.link_receipt_to_transaction(
    p_receipt_id INTEGER,
    p_transaction_id INTEGER,
    p_method VARCHAR(50) DEFAULT 'manual',
    p_confidence NUMERIC(3,2) DEFAULT 1.00
) RETURNS BOOLEAN AS $$
BEGIN
    UPDATE finance.receipts
    SET linked_transaction_id = p_transaction_id,
        link_confidence = p_confidence,
        link_method = p_method,
        linked_at = NOW(),
        updated_at = NOW()
    WHERE id = p_receipt_id;

    -- Mark transaction as having receipt processed
    UPDATE finance.transactions
    SET receipt_processed = TRUE
    WHERE id = p_transaction_id;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Function to find matching transaction for a receipt
CREATE OR REPLACE FUNCTION finance.find_matching_transaction(
    p_receipt_id INTEGER
) RETURNS TABLE (
    transaction_id INTEGER,
    match_type VARCHAR(50),
    confidence NUMERIC(3,2)
) AS $$
DECLARE
    v_receipt RECORD;
BEGIN
    -- Get receipt details
    SELECT receipt_date, total_amount, vendor
    INTO v_receipt
    FROM finance.receipts
    WHERE id = p_receipt_id;

    -- Look for exact match (same date, same amount)
    RETURN QUERY
    SELECT
        t.id AS transaction_id,
        'exact_date_amount'::VARCHAR(50) AS match_type,
        1.00::NUMERIC(3,2) AS confidence
    FROM finance.transactions t
    WHERE t.date = v_receipt.receipt_date
      AND ABS(t.amount) = v_receipt.total_amount
      AND t.receipt_processed = FALSE
      AND t.is_quarantined = FALSE
    LIMIT 1;

    IF NOT FOUND THEN
        -- Look for fuzzy match (±1 day, same amount)
        RETURN QUERY
        SELECT
            t.id AS transaction_id,
            'fuzzy_date_amount'::VARCHAR(50) AS match_type,
            0.85::NUMERIC(3,2) AS confidence
        FROM finance.transactions t
        WHERE t.date BETWEEN v_receipt.receipt_date - 1 AND v_receipt.receipt_date + 1
          AND ABS(t.amount) = v_receipt.total_amount
          AND t.receipt_processed = FALSE
          AND t.is_quarantined = FALSE
        ORDER BY ABS(t.date - v_receipt.receipt_date)
        LIMIT 1;
    END IF;

    IF NOT FOUND THEN
        -- Look for amount-only match within 3 days
        RETURN QUERY
        SELECT
            t.id AS transaction_id,
            'amount_only'::VARCHAR(50) AS match_type,
            0.60::NUMERIC(3,2) AS confidence
        FROM finance.transactions t
        WHERE t.date BETWEEN v_receipt.receipt_date - 3 AND v_receipt.receipt_date + 3
          AND ABS(t.amount) = v_receipt.total_amount
          AND t.receipt_processed = FALSE
          AND t.is_quarantined = FALSE
        ORDER BY ABS(t.date - v_receipt.receipt_date)
        LIMIT 1;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Auto-update timestamp trigger
CREATE OR REPLACE FUNCTION finance.update_receipt_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_receipts_updated_at
    BEFORE UPDATE ON finance.receipts
    FOR EACH ROW
    EXECUTE FUNCTION finance.update_receipt_timestamp();

-- ============================================================================
-- VIEWS
-- ============================================================================

-- View for unlinked receipts awaiting matching
CREATE OR REPLACE VIEW finance.v_receipts_pending_link AS
SELECT
    r.id AS receipt_id,
    r.vendor,
    r.receipt_date,
    r.total_amount,
    r.store_name,
    r.invoice_number,
    r.created_at,
    (SELECT COUNT(*) FROM finance.receipt_items ri WHERE ri.receipt_id = r.id) AS item_count
FROM finance.receipts r
WHERE r.linked_transaction_id IS NULL
  AND r.parse_status = 'success'
ORDER BY r.receipt_date DESC;

-- View for receipt summary with transaction link status
CREATE OR REPLACE VIEW finance.v_receipt_summary AS
SELECT
    r.id,
    r.vendor,
    r.receipt_date,
    r.store_name,
    r.total_amount,
    r.parse_status,
    r.linked_transaction_id IS NOT NULL AS is_linked,
    r.link_confidence,
    t.merchant_name AS linked_merchant,
    (SELECT COUNT(*) FROM finance.receipt_items ri WHERE ri.receipt_id = r.id) AS item_count,
    r.created_at
FROM finance.receipts r
LEFT JOIN finance.transactions t ON t.id = r.linked_transaction_id
ORDER BY r.receipt_date DESC;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE finance.receipts IS 'Raw receipt metadata from email PDFs';
COMMENT ON TABLE finance.receipt_items IS 'Parsed line items from receipts';
COMMENT ON TABLE finance.receipt_raw_text IS 'Raw extracted text for debugging/re-parsing';
COMMENT ON TABLE finance.receipt_parsers IS 'Vendor-specific parser configurations';

COMMENT ON COLUMN finance.receipts.gmail_message_id IS 'Unique Gmail message ID for idempotency';
COMMENT ON COLUMN finance.receipts.pdf_hash IS 'SHA256 hash of PDF content for deduplication';
COMMENT ON COLUMN finance.receipts.invoice_number IS 'Vendor invoice/receipt number from PDF';
COMMENT ON COLUMN finance.receipts.link_confidence IS 'Confidence score 0-1 for transaction match';
