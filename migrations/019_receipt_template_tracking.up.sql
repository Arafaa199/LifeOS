-- Migration 018: Receipt template tracking for drift detection
-- Adds columns to detect when vendor PDF formats change

-- Add template tracking columns
ALTER TABLE finance.receipts
ADD COLUMN IF NOT EXISTS template_hash TEXT,
ADD COLUMN IF NOT EXISTS parse_version TEXT DEFAULT 'carrefour_v1';

-- Add index for template_hash lookups (to detect new templates)
CREATE INDEX IF NOT EXISTS idx_receipts_template_hash
ON finance.receipts (template_hash)
WHERE template_hash IS NOT NULL;

-- Add known_templates table to track seen templates
CREATE TABLE IF NOT EXISTS finance.receipt_templates (
    id SERIAL PRIMARY KEY,
    vendor TEXT NOT NULL,
    template_hash TEXT NOT NULL UNIQUE,
    parse_version TEXT NOT NULL,
    sample_receipt_id INTEGER REFERENCES finance.receipts(id),
    first_seen_at TIMESTAMPTZ DEFAULT NOW(),
    status TEXT DEFAULT 'approved',  -- 'approved', 'needs_review', 'rejected'
    notes TEXT
);

-- Seed with current Carrefour template (will be updated with actual hash)
-- INSERT INTO finance.receipt_templates (vendor, template_hash, parse_version, status, notes)
-- VALUES ('carrefour_uae', 'PENDING', 'carrefour_v1', 'approved', 'Initial template')
-- ON CONFLICT (template_hash) DO NOTHING;

COMMENT ON COLUMN finance.receipts.template_hash IS 'SHA256 of normalized PDF header structure - detects format changes';
COMMENT ON COLUMN finance.receipts.parse_version IS 'Parser version used (e.g., carrefour_v1)';
COMMENT ON TABLE finance.receipt_templates IS 'Known/approved PDF templates per vendor for drift detection';
