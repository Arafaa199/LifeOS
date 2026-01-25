-- Verification queries for migration 079: Receipt Item Brands

-- 1. Check schema changes
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'finance'
  AND table_name = 'receipt_items'
  AND column_name IN ('brand', 'brand_confidence', 'brand_source')
ORDER BY column_name;

-- 2. Check known_brands table
SELECT COUNT(*) AS brand_count FROM finance.known_brands;
SELECT brand_name, category FROM finance.known_brands ORDER BY category, brand_name LIMIT 15;

-- 3. Test extract_brand function
SELECT
    description,
    (finance.extract_brand(description)).*
FROM (VALUES
    ('Nestle Lion Wild Cereal 410 g'),
    ('Kinder Country Milky Filling Chocolate Bar'),
    ('Almarai Low Fat Fresh Milk, 1L'),
    ('Carrot Australia 400-500 g'),
    ('Fresh Tomatoes Local 500g'),
    ('Unknown Brand Product XYZ')
) AS t(description);

-- 4. Check brand coverage view
SELECT * FROM finance.v_brand_coverage;

-- 5. Check brand spending view (will be empty until receipts are processed)
SELECT * FROM finance.v_brand_spending LIMIT 10;

-- 6. Backfill brands for existing receipt items using DB function
UPDATE finance.receipt_items ri
SET
    brand = (finance.extract_brand(ri.item_description)).brand,
    brand_confidence = (finance.extract_brand(ri.item_description)).confidence,
    brand_source = (finance.extract_brand(ri.item_description)).source
WHERE ri.brand IS NULL
  AND ri.item_description IS NOT NULL;

-- 7. Re-check coverage after backfill
SELECT * FROM finance.v_brand_coverage;
