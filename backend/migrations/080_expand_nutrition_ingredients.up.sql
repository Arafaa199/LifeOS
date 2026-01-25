-- Migration 080: Expand nutrition ingredients for UAE grocery matching
-- Objective: Improve match rate from ~5% to 50%+
-- Context: Adding common Carrefour UAE items based on receipt analysis

-- Add new ingredients (UAE grocery store common items)
INSERT INTO nutrition.ingredients (name, calories_per_100g, protein_per_100g, carbs_per_100g, fat_per_100g, category, is_whole_food)
VALUES
    -- Dairy
    ('Milk (Low Fat)', 42.0, 3.4, 5.0, 1.0, 'dairy', true),
    ('Milk (Skim)', 34.0, 3.4, 5.0, 0.1, 'dairy', true),
    ('Greek Yogurt (Low Fat)', 73.0, 9.0, 4.0, 2.0, 'dairy', true),
    ('Cheese (Camembert)', 300.0, 20.0, 0.5, 24.0, 'dairy', true),
    ('Cheese (Areesh)', 98.0, 17.0, 3.4, 1.5, 'dairy', true),
    ('Cheese (Philadelphia)', 342.0, 6.0, 4.0, 34.0, 'dairy', false),

    -- Vegetables
    ('Cucumber', 15.0, 0.7, 3.6, 0.1, 'vegetable', true),
    ('Mushrooms (White)', 22.0, 3.1, 3.3, 0.3, 'vegetable', true),
    ('Capsicum (Green)', 20.0, 0.9, 4.6, 0.2, 'vegetable', true),
    ('Capsicum (Red)', 31.0, 1.0, 6.0, 0.3, 'vegetable', true),
    ('Lettuce (Romaine)', 17.0, 1.2, 3.3, 0.3, 'vegetable', true),
    ('Lettuce (Iceberg)', 14.0, 0.9, 3.0, 0.1, 'vegetable', true),
    ('Garlic', 149.0, 6.4, 33.0, 0.5, 'vegetable', true),
    ('Onion', 40.0, 1.1, 9.3, 0.1, 'vegetable', true),
    ('Tomato', 18.0, 0.9, 3.9, 0.2, 'vegetable', true),
    ('Potato', 77.0, 2.0, 17.0, 0.1, 'vegetable', true),
    ('Carrot', 41.0, 0.9, 10.0, 0.2, 'vegetable', true),
    ('Zucchini', 17.0, 1.2, 3.1, 0.3, 'vegetable', true),
    ('Red Onion', 40.0, 1.1, 9.3, 0.1, 'vegetable', true),

    -- Legumes & Grains
    ('Lentils (Red)', 353.0, 25.0, 60.0, 1.0, 'legume', true),
    ('Masoor Dal', 353.0, 25.0, 60.0, 1.0, 'legume', true),
    ('Lentils (cooked)', 116.0, 9.0, 20.0, 0.4, 'legume', true),
    ('Chickpeas (dry)', 364.0, 19.0, 61.0, 6.0, 'legume', true),
    ('Chickpeas (cooked)', 164.0, 8.9, 27.0, 2.6, 'legume', true),
    ('Quinoa (dry)', 368.0, 14.0, 64.0, 6.1, 'grain', true),

    -- Meat & Protein
    ('Beef Ribeye', 291.0, 24.0, 0.0, 21.0, 'meat', true),
    ('Beef Mince (Lean)', 137.0, 21.0, 0.0, 5.0, 'meat', true),
    ('Beef Mince', 254.0, 17.0, 0.0, 20.0, 'meat', true),
    ('Lamb (Leg)', 168.0, 25.0, 0.0, 7.0, 'meat', true),
    ('Turkey Breast', 104.0, 24.0, 0.0, 0.7, 'meat', true),

    -- Snacks & Processed
    ('Dark Chocolate', 598.0, 7.8, 46.0, 43.0, 'snack', false),
    ('Chocolate (Dark 90%)', 604.0, 8.0, 25.0, 52.0, 'snack', false),
    ('Potato Chips', 536.0, 7.0, 53.0, 35.0, 'snack', false),
    ('Rice Cakes', 387.0, 8.0, 81.0, 3.0, 'snack', false),
    ('Rice Cake (Brown)', 387.0, 8.0, 81.0, 3.0, 'snack', false),
    ('Breakfast Cereal', 379.0, 5.0, 84.0, 1.5, 'grain', false),
    ('Chocolate Biscuits', 502.0, 6.0, 62.0, 25.0, 'snack', false),
    ('Granola Bar', 471.0, 8.0, 64.0, 20.0, 'snack', false),

    -- Beverages
    ('Gatorade', 26.0, 0.0, 6.0, 0.0, 'beverage', false),
    ('Sports Drink', 26.0, 0.0, 6.0, 0.0, 'beverage', false),
    ('Coconut Water', 19.0, 0.7, 3.7, 0.2, 'beverage', true),
    ('Coconut Juice', 19.0, 0.7, 3.7, 0.2, 'beverage', true),
    ('Orange Juice', 45.0, 0.7, 10.4, 0.2, 'beverage', true),

    -- Fruits
    ('Mango', 60.0, 0.8, 15.0, 0.4, 'fruit', true),
    ('Watermelon', 30.0, 0.6, 7.6, 0.2, 'fruit', true),
    ('Grapes', 69.0, 0.7, 18.0, 0.2, 'fruit', true),
    ('Strawberries', 32.0, 0.7, 7.7, 0.3, 'fruit', true),

    -- Spreads & Condiments
    ('Honey', 304.0, 0.3, 82.0, 0.0, 'condiment', true),
    ('Hummus', 166.0, 8.0, 14.0, 10.0, 'condiment', false)

-- Not using ON CONFLICT since name has no unique constraint
;

COMMENT ON TABLE nutrition.ingredients IS 'Nutrition data for food items. Expanded 2026-01-26 for UAE grocery matching.';
