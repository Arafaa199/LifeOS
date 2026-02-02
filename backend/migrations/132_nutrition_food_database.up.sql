-- Migration 132: Nutrition food reference database
-- Denormalized wide table for USDA FoodData Central + Open Food Facts

CREATE TABLE IF NOT EXISTS nutrition.foods (
    id SERIAL PRIMARY KEY,
    fdc_id INTEGER,
    barcode VARCHAR(50),
    name TEXT NOT NULL,
    brand TEXT,
    source VARCHAR(20) NOT NULL CHECK (source IN ('usda_foundation', 'usda_sr_legacy', 'usda_branded', 'off', 'manual')),
    calories_per_100g NUMERIC(9,2),
    protein_per_100g NUMERIC(9,2),
    carbs_per_100g NUMERIC(9,2),
    fat_per_100g NUMERIC(9,2),
    fiber_per_100g NUMERIC(9,2),
    sugar_per_100g NUMERIC(9,2),
    sodium_mg_per_100g NUMERIC(9,2),
    serving_size_g NUMERIC(9,2),
    serving_description TEXT,
    category TEXT,
    is_whole_food BOOLEAN DEFAULT FALSE,
    data_quality SMALLINT NOT NULL DEFAULT 3 CHECK (data_quality BETWEEN 1 AND 3),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_foods_fdc_id ON nutrition.foods (fdc_id) WHERE fdc_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_foods_barcode_source ON nutrition.foods (barcode, source) WHERE barcode IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_foods_name_trgm ON nutrition.foods USING gin (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_foods_brand_trgm ON nutrition.foods USING gin (brand gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_foods_barcode ON nutrition.foods (barcode) WHERE barcode IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_foods_source ON nutrition.foods (source);
CREATE INDEX IF NOT EXISTS idx_foods_data_quality ON nutrition.foods (data_quality);

-- Search function: trigram similarity, manual curations ranked first via data_quality
CREATE OR REPLACE FUNCTION nutrition.search_foods(
    p_query TEXT,
    p_limit INT DEFAULT 10,
    p_prefer_quality BOOLEAN DEFAULT TRUE
)
RETURNS TABLE (
    id INT,
    fdc_id INT,
    barcode VARCHAR(50),
    name TEXT,
    brand TEXT,
    source VARCHAR(20),
    calories_per_100g NUMERIC(9,2),
    protein_per_100g NUMERIC(9,2),
    carbs_per_100g NUMERIC(9,2),
    fat_per_100g NUMERIC(9,2),
    fiber_per_100g NUMERIC(9,2),
    serving_size_g NUMERIC(9,2),
    serving_description TEXT,
    category TEXT,
    data_quality SMALLINT,
    relevance REAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        f.id, f.fdc_id, f.barcode, f.name, f.brand, f.source,
        f.calories_per_100g, f.protein_per_100g, f.carbs_per_100g,
        f.fat_per_100g, f.fiber_per_100g,
        f.serving_size_g, f.serving_description, f.category,
        f.data_quality,
        similarity(f.name, p_query)::REAL AS relevance
    FROM nutrition.foods f
    WHERE f.name % p_query
       OR f.brand % p_query
    ORDER BY
        CASE WHEN p_prefer_quality THEN f.data_quality ELSE 3 END ASC,
        similarity(f.name, p_query) DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

-- Barcode lookup: checks nutrition.ingredients first (manual curations), then nutrition.foods
CREATE OR REPLACE FUNCTION nutrition.lookup_barcode(p_barcode TEXT)
RETURNS TABLE (
    id INT,
    name TEXT,
    brand TEXT,
    source VARCHAR(20),
    calories_per_100g NUMERIC(9,2),
    protein_per_100g NUMERIC(9,2),
    carbs_per_100g NUMERIC(9,2),
    fat_per_100g NUMERIC(9,2),
    fiber_per_100g NUMERIC(9,2),
    serving_size_g NUMERIC(9,2),
    serving_description TEXT,
    data_quality SMALLINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        f.id, f.name, f.brand, f.source,
        f.calories_per_100g, f.protein_per_100g, f.carbs_per_100g,
        f.fat_per_100g, f.fiber_per_100g,
        f.serving_size_g, f.serving_description, f.data_quality
    FROM nutrition.foods f
    WHERE f.barcode = p_barcode
    ORDER BY f.data_quality ASC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql STABLE;
