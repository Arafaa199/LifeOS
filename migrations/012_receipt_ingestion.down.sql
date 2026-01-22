-- Migration: 012_receipt_ingestion (ROLLBACK)
-- Purpose: Remove receipt ingestion system

-- Drop views first
DROP VIEW IF EXISTS finance.v_receipt_summary;
DROP VIEW IF EXISTS finance.v_receipts_pending_link;

-- Drop functions
DROP FUNCTION IF EXISTS finance.find_matching_transaction(INTEGER);
DROP FUNCTION IF EXISTS finance.link_receipt_to_transaction(INTEGER, INTEGER, VARCHAR, NUMERIC);
DROP FUNCTION IF EXISTS finance.update_receipt_timestamp();

-- Drop trigger
DROP TRIGGER IF EXISTS trg_receipts_updated_at ON finance.receipts;

-- Drop tables (in reverse dependency order)
DROP TABLE IF EXISTS finance.receipt_raw_text;
DROP TABLE IF EXISTS finance.receipt_items;
DROP TABLE IF EXISTS finance.receipt_parsers;
DROP TABLE IF EXISTS finance.receipts;
