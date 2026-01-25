-- Verification Queries for Grocery → Nutrition View
-- Date: 2026-01-25

-- 1. Check view exists
SELECT EXISTS (
    SELECT 1 FROM information_schema.views
    WHERE table_schema = 'nutrition' AND table_name = 'v_grocery_nutrition'
) as view_exists;

-- 2. Total items and match type distribution
SELECT
    match_type,
    COUNT(*) as item_count,
    ROUND(AVG(match_confidence)::NUMERIC, 2) as avg_confidence,
    COUNT(ingredient_id) as items_with_nutrition
FROM nutrition.v_grocery_nutrition
GROUP BY match_type
ORDER BY
    CASE match_type
        WHEN 'barcode' THEN 1
        WHEN 'fuzzy_name' THEN 2
        WHEN 'unmatched' THEN 3
    END;

-- 3. Sample matched items (barcode)
SELECT
    item_description,
    barcode,
    ingredient_name,
    calories_per_100g,
    protein_per_100g,
    match_type,
    match_confidence
FROM nutrition.v_grocery_nutrition
WHERE match_type = 'barcode'
LIMIT 5;

-- 4. Sample matched items (fuzzy name)
SELECT
    item_description,
    ingredient_name,
    calories_per_100g,
    match_type,
    ROUND(match_confidence::NUMERIC, 2) as confidence
FROM nutrition.v_grocery_nutrition
WHERE match_type = 'fuzzy_name'
LIMIT 5;

-- 5. Unmatched items summary
SELECT
    COUNT(*) as unmatched_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM nutrition.v_grocery_nutrition), 1) as unmatched_pct
FROM nutrition.v_grocery_nutrition
WHERE match_type = 'unmatched';

-- 6. Nutrition data completeness for matched items
SELECT
    match_type,
    COUNT(*) as total,
    COUNT(calories_per_100g) as has_calories,
    COUNT(protein_per_100g) as has_protein,
    COUNT(carbs_per_100g) as has_carbs,
    COUNT(fat_per_100g) as has_fat
FROM nutrition.v_grocery_nutrition
WHERE match_type IN ('barcode', 'fuzzy_name')
GROUP BY match_type;

-- 7. Receipt-level summary
SELECT
    receipt_id,
    COUNT(*) as total_items,
    COUNT(ingredient_id) as items_with_nutrition,
    ROUND(100.0 * COUNT(ingredient_id) / COUNT(*), 1) as nutrition_pct
FROM nutrition.v_grocery_nutrition
GROUP BY receipt_id
ORDER BY receipt_id;

-- 8. Top unmatched items (by line total)
SELECT
    item_description,
    barcode,
    quantity,
    line_total
FROM nutrition.v_grocery_nutrition
WHERE match_type = 'unmatched'
ORDER BY line_total DESC
LIMIT 10;
