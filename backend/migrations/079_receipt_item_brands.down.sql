-- Rollback migration 079

DROP VIEW IF EXISTS finance.v_brand_coverage;
DROP VIEW IF EXISTS finance.v_brand_spending;
DROP FUNCTION IF EXISTS finance.extract_brand(TEXT);
DROP TABLE IF EXISTS finance.known_brands;

ALTER TABLE finance.receipt_items
DROP CONSTRAINT IF EXISTS chk_brand_source,
DROP COLUMN IF EXISTS brand_source,
DROP COLUMN IF EXISTS brand_confidence,
DROP COLUMN IF EXISTS brand;
