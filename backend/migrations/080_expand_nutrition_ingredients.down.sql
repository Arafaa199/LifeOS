-- Migration 080 down: Remove added nutrition ingredients
-- Note: Only removes ingredients added in this migration

DELETE FROM nutrition.ingredients WHERE name IN (
    'Milk (Low Fat)', 'Milk (Skim)', 'Greek Yogurt (Low Fat)',
    'Cheese (Camembert)', 'Cheese (Areesh)', 'Cheese (Philadelphia)',
    'Cucumber', 'Mushrooms (White)', 'Capsicum (Green)', 'Capsicum (Red)',
    'Lettuce (Romaine)', 'Lettuce (Iceberg)', 'Garlic', 'Onion', 'Tomato',
    'Potato', 'Carrot', 'Zucchini',
    'Lentils (Red/Masoor Dal)', 'Lentils (cooked)', 'Chickpeas (dry)', 'Chickpeas (cooked)',
    'Quinoa (dry)',
    'Beef (Ribeye)', 'Beef (Mince, Lean)', 'Lamb (Leg)', 'Turkey Breast',
    'Dark Chocolate (85%+)', 'Dark Chocolate (70%)', 'Potato Chips', 'Rice Cakes',
    'Breakfast Cereal (sweetened)', 'Biscuits (chocolate coated)', 'Granola Bar',
    'Sports Drink (Gatorade)', 'Coconut Water', 'Orange Juice',
    'Mango', 'Watermelon', 'Grapes', 'Strawberries',
    'Honey', 'Hummus'
);
