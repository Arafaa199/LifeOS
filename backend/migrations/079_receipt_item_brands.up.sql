-- Migration 079: Add brand extraction support to receipt_items
-- Enables brand-level analytics for grocery spending

-- Add brand columns to receipt_items
ALTER TABLE finance.receipt_items
ADD COLUMN IF NOT EXISTS brand VARCHAR(100),
ADD COLUMN IF NOT EXISTS brand_confidence NUMERIC(3,2) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS brand_source VARCHAR(20) DEFAULT NULL;

-- Add constraint for brand_source values
ALTER TABLE finance.receipt_items
ADD CONSTRAINT chk_brand_source
CHECK (brand_source IS NULL OR brand_source IN ('known_list', 'position', 'manual', 'ai'));

-- Index for brand queries
CREATE INDEX IF NOT EXISTS idx_receipt_items_brand
ON finance.receipt_items(brand) WHERE brand IS NOT NULL;

-- Known brands reference table for high-confidence matching
CREATE TABLE IF NOT EXISTS finance.known_brands (
    id SERIAL PRIMARY KEY,
    brand_name VARCHAR(100) NOT NULL UNIQUE,
    aliases TEXT[] DEFAULT '{}',  -- Alternative spellings/names
    category VARCHAR(50),          -- Food category (dairy, cereal, condiments, etc.)
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed with common grocery brands from UAE
INSERT INTO finance.known_brands (brand_name, aliases, category) VALUES
    -- Cereals & Breakfast
    ('Nestle', ARRAY['Nestlé', 'NESTLE'], 'cereals'),
    ('Kelloggs', ARRAY['Kellogg''s', 'KELLOGGS', 'Kellogg'], 'cereals'),
    ('Quaker', ARRAY['QUAKER'], 'cereals'),

    -- Chocolate & Snacks
    ('Kinder', ARRAY['KINDER', 'Ferrero Kinder'], 'chocolate'),
    ('Galaxy', ARRAY['GALAXY'], 'chocolate'),
    ('Cadbury', ARRAY['CADBURY', 'Cadburys'], 'chocolate'),
    ('Lindt', ARRAY['LINDT'], 'chocolate'),
    ('Toblerone', ARRAY['TOBLERONE'], 'chocolate'),

    -- Spreads & Jams
    ('Bonne Maman', ARRAY['BONNE MAMAN', 'BonneMaman'], 'spreads'),
    ('Nutella', ARRAY['NUTELLA', 'Ferrero Nutella'], 'spreads'),
    ('Skippy', ARRAY['SKIPPY'], 'spreads'),

    -- Rice & Grains
    ('Tilda', ARRAY['TILDA'], 'grains'),
    ('Basmati', ARRAY['BASMATI'], 'grains'),
    ('Uncle Bens', ARRAY['Uncle Ben''s', 'UNCLE BENS'], 'grains'),

    -- Spices & Seasonings
    ('Bayara', ARRAY['BAYARA'], 'spices'),
    ('Maggi', ARRAY['MAGGI', 'Nestle Maggi'], 'seasonings'),

    -- Dairy
    ('Almarai', ARRAY['ALMARAI', 'Al Marai'], 'dairy'),
    ('Lurpak', ARRAY['LURPAK'], 'dairy'),
    ('Philadelphia', ARRAY['PHILADELPHIA', 'Philly'], 'dairy'),
    ('Kiri', ARRAY['KIRI'], 'dairy'),
    ('Puck', ARRAY['PUCK'], 'dairy'),

    -- Beverages
    ('Vimto', ARRAY['VIMTO'], 'beverages'),
    ('Tang', ARRAY['TANG'], 'beverages'),
    ('Nescafe', ARRAY['NESCAFE', 'Nescafé', 'Nestle Nescafe'], 'beverages'),
    ('Lipton', ARRAY['LIPTON'], 'beverages'),

    -- Bakery
    ('Modern Bakery', ARRAY['MODERN BAKERY', 'Modern'], 'bakery'),
    ('Americana', ARRAY['AMERICANA'], 'bakery'),

    -- Health & Organic
    ('Earth Goods', ARRAY['EARTH GOODS', 'EarthGoods'], 'organic'),
    ('Goody', ARRAY['GOODY'], 'pantry'),

    -- Personal Care (sometimes in grocery)
    ('Dettol', ARRAY['DETTOL'], 'personal_care'),
    ('Fairy', ARRAY['FAIRY'], 'cleaning')
ON CONFLICT (brand_name) DO NOTHING;

-- Function to extract brand from item description
CREATE OR REPLACE FUNCTION finance.extract_brand(description TEXT)
RETURNS TABLE(brand VARCHAR(100), confidence NUMERIC(3,2), source VARCHAR(20)) AS $$
DECLARE
    clean_desc TEXT;
    first_word TEXT;
    matched_brand RECORD;
BEGIN
    -- Normalize description
    clean_desc := UPPER(TRIM(description));

    -- Try matching against known brands (high confidence)
    FOR matched_brand IN
        SELECT kb.brand_name
        FROM finance.known_brands kb
        WHERE kb.is_active
        AND (
            clean_desc LIKE UPPER(kb.brand_name) || ' %'
            OR clean_desc LIKE '% ' || UPPER(kb.brand_name) || ' %'
            OR EXISTS (
                SELECT 1 FROM UNNEST(kb.aliases) alias
                WHERE clean_desc LIKE UPPER(alias) || ' %'
                OR clean_desc LIKE '% ' || UPPER(alias) || ' %'
            )
        )
        LIMIT 1
    LOOP
        RETURN QUERY SELECT matched_brand.brand_name::VARCHAR(100), 0.95::NUMERIC(3,2), 'known_list'::VARCHAR(20);
        RETURN;
    END LOOP;

    -- Fallback: First word if capitalized and > 2 chars (lower confidence)
    first_word := SPLIT_PART(TRIM(description), ' ', 1);
    IF LENGTH(first_word) > 2
       AND first_word ~ '^[A-Z]'  -- Starts with capital
       AND first_word !~ '^\d'    -- Doesn't start with digit
       AND first_word NOT IN ('The', 'Fresh', 'Organic', 'Natural', 'Premium', 'Classic', 'Original')
    THEN
        RETURN QUERY SELECT INITCAP(first_word)::VARCHAR(100), 0.60::NUMERIC(3,2), 'position'::VARCHAR(20);
        RETURN;
    END IF;

    -- No brand detected
    RETURN QUERY SELECT NULL::VARCHAR(100), NULL::NUMERIC(3,2), NULL::VARCHAR(20);
END;
$$ LANGUAGE plpgsql STABLE;

-- View for brand analytics
CREATE OR REPLACE VIEW finance.v_brand_spending AS
SELECT
    ri.brand,
    ri.brand_confidence,
    COUNT(*) AS item_count,
    SUM(ri.line_total) AS total_spent,
    AVG(ri.line_total) AS avg_item_price,
    COUNT(DISTINCT r.id) AS receipt_count,
    MIN(r.email_received_at) AS first_purchase,
    MAX(r.email_received_at) AS last_purchase
FROM finance.receipt_items ri
JOIN finance.receipts r ON r.id = ri.receipt_id
WHERE ri.brand IS NOT NULL
GROUP BY ri.brand, ri.brand_confidence
ORDER BY total_spent DESC;

-- View for brand coverage metrics
CREATE OR REPLACE VIEW finance.v_brand_coverage AS
SELECT
    COUNT(*) AS total_items,
    COUNT(brand) AS items_with_brand,
    ROUND(100.0 * COUNT(brand) / NULLIF(COUNT(*), 0), 1) AS coverage_pct,
    COUNT(*) FILTER (WHERE brand_source = 'known_list') AS known_list_matches,
    COUNT(*) FILTER (WHERE brand_source = 'position') AS position_matches,
    COUNT(*) FILTER (WHERE brand_source = 'manual') AS manual_entries,
    ROUND(AVG(brand_confidence) FILTER (WHERE brand_confidence IS NOT NULL), 2) AS avg_confidence
FROM finance.receipt_items;

COMMENT ON TABLE finance.known_brands IS 'Reference table of known grocery brands for high-confidence matching';
COMMENT ON COLUMN finance.receipt_items.brand IS 'Extracted brand name from item description';
COMMENT ON COLUMN finance.receipt_items.brand_confidence IS 'Confidence score 0.00-1.00 for brand extraction';
COMMENT ON COLUMN finance.receipt_items.brand_source IS 'How brand was determined: known_list, position, manual, ai';
