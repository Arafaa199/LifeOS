-- Migration: Create Grocery → Nutrition View
-- Purpose: Link grocery purchases to nutrition data
-- Date: 2026-01-25

-- Enable pg_trgm extension for fuzzy text matching
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Create view joining receipt items with nutrition ingredients
CREATE OR REPLACE VIEW nutrition.v_grocery_nutrition AS
WITH barcode_matches AS (
    -- Exact barcode matches
    SELECT
        ri.id as receipt_item_id,
        ri.receipt_id,
        ri.item_description,
        ri.item_description_clean,
        ri.item_code as barcode,
        ri.quantity,
        ri.unit_price,
        ri.line_total,
        ing.id as ingredient_id,
        ing.name as ingredient_name,
        ing.calories_per_100g,
        ing.protein_per_100g,
        ing.carbs_per_100g,
        ing.fat_per_100g,
        ing.fiber_per_100g,
        ing.sugar_per_100g,
        ing.sodium_mg_per_100g,
        ing.serving_size_g,
        ing.category as nutrition_category,
        'barcode' as match_type,
        1.0 as match_confidence
    FROM finance.receipt_items ri
    INNER JOIN nutrition.ingredients ing ON ri.item_code = ing.barcode
    WHERE ri.item_code IS NOT NULL
),
fuzzy_name_matches AS (
    -- Fuzzy name matches for items without barcode matches
    SELECT DISTINCT ON (ri.id)
        ri.id as receipt_item_id,
        ri.receipt_id,
        ri.item_description,
        ri.item_description_clean,
        ri.item_code as barcode,
        ri.quantity,
        ri.unit_price,
        ri.line_total,
        ing.id as ingredient_id,
        ing.name as ingredient_name,
        ing.calories_per_100g,
        ing.protein_per_100g,
        ing.carbs_per_100g,
        ing.fat_per_100g,
        ing.fiber_per_100g,
        ing.sugar_per_100g,
        ing.sodium_mg_per_100g,
        ing.serving_size_g,
        ing.category as nutrition_category,
        'fuzzy_name' as match_type,
        -- Similarity score using trigram similarity
        GREATEST(
            similarity(LOWER(ri.item_description_clean), LOWER(ing.name)),
            similarity(LOWER(ri.item_description), LOWER(ing.name))
        ) as match_confidence
    FROM finance.receipt_items ri
    CROSS JOIN nutrition.ingredients ing
    WHERE ri.id NOT IN (SELECT receipt_item_id FROM barcode_matches)
    AND (
        similarity(LOWER(ri.item_description_clean), LOWER(ing.name)) > 0.3
        OR similarity(LOWER(ri.item_description), LOWER(ing.name)) > 0.3
    )
    ORDER BY ri.id, match_confidence DESC
),
all_matches AS (
    SELECT * FROM barcode_matches
    UNION ALL
    SELECT * FROM fuzzy_name_matches
),
unmatched_items AS (
    -- Items with no matches
    SELECT
        ri.id as receipt_item_id,
        ri.receipt_id,
        ri.item_description,
        ri.item_description_clean,
        ri.item_code as barcode,
        ri.quantity,
        ri.unit_price,
        ri.line_total,
        NULL::INTEGER as ingredient_id,
        NULL::VARCHAR as ingredient_name,
        NULL::NUMERIC as calories_per_100g,
        NULL::NUMERIC as protein_per_100g,
        NULL::NUMERIC as carbs_per_100g,
        NULL::NUMERIC as fat_per_100g,
        NULL::NUMERIC as fiber_per_100g,
        NULL::NUMERIC as sugar_per_100g,
        NULL::NUMERIC as sodium_mg_per_100g,
        NULL::NUMERIC as serving_size_g,
        NULL::VARCHAR as nutrition_category,
        'unmatched' as match_type,
        0.0 as match_confidence
    FROM finance.receipt_items ri
    WHERE ri.id NOT IN (SELECT receipt_item_id FROM all_matches)
)
SELECT * FROM all_matches
UNION ALL
SELECT * FROM unmatched_items
ORDER BY receipt_id, receipt_item_id;

COMMENT ON VIEW nutrition.v_grocery_nutrition IS 'Links grocery purchases to nutrition data via barcode (exact) or name (fuzzy) matching';
