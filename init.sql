-- ============================================================================
-- NEXUS: Personal Life Data Hub
-- Complete Database Schema
-- ============================================================================

-- Create schemas
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS health;
CREATE SCHEMA IF NOT EXISTS nutrition;
CREATE SCHEMA IF NOT EXISTS finance;
CREATE SCHEMA IF NOT EXISTS notes;
CREATE SCHEMA IF NOT EXISTS home;

-- ============================================================================
-- CORE SCHEMA: Shared reference tables and daily summaries
-- ============================================================================

-- Global tags for cross-domain categorization
CREATE TABLE core.tags (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL,
    category VARCHAR(30),  -- 'health', 'food', 'finance', 'general'
    color VARCHAR(7),      -- Hex color for UI
    created_at TIMESTAMP DEFAULT NOW()
);

-- Pre-computed daily rollup (updated by n8n nightly)
CREATE TABLE core.daily_summary (
    date DATE PRIMARY KEY,

    -- Health metrics
    weight_kg DECIMAL(5,2),
    body_fat_pct DECIMAL(4,1),
    recovery_score INT,
    hrv_avg INT,
    rhr_avg INT,
    sleep_hours DECIMAL(3,1),
    sleep_quality_score INT,
    strain DECIMAL(4,1),
    steps INT,
    active_calories INT,

    -- Nutrition aggregates
    calories_consumed INT,
    protein_g INT,
    carbs_g INT,
    fat_g INT,
    fiber_g INT,
    water_ml INT,
    meals_logged INT,
    calories_confidence VARCHAR(10) DEFAULT 'high',  -- 'high', 'medium', 'low'

    -- Finance aggregates
    total_spent DECIMAL(10,2),
    grocery_spent DECIMAL(10,2),
    eating_out_spent DECIMAL(10,2),

    -- Activity
    workouts_count INT DEFAULT 0,
    notes_created INT DEFAULT 0,

    -- Meta
    data_completeness DECIMAL(3,2),  -- 0.00 to 1.00
    updated_at TIMESTAMP DEFAULT NOW()
);

-- User preferences and settings
CREATE TABLE core.settings (
    key VARCHAR(50) PRIMARY KEY,
    value JSONB NOT NULL,
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Insert default settings
INSERT INTO core.settings (key, value) VALUES
    ('units', '{"weight": "kg", "height": "cm", "volume": "ml"}'),
    ('goals', '{"daily_calories": 2000, "daily_protein_g": 150, "daily_water_ml": 3000, "target_weight_kg": null}'),
    ('integrations', '{"whoop": true, "apple_health": true, "home_assistant": true}');

-- ============================================================================
-- HEALTH SCHEMA: Biometrics, sleep, workouts
-- ============================================================================

-- Raw health metrics (time-series)
CREATE TABLE health.metrics (
    id SERIAL PRIMARY KEY,
    recorded_at TIMESTAMP NOT NULL,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    source VARCHAR(30) NOT NULL,  -- 'whoop', 'scale', 'apple_health', 'home_assistant', 'manual'
    metric_type VARCHAR(30) NOT NULL,
    value DECIMAL(10,2) NOT NULL,
    unit VARCHAR(10),
    metadata JSONB,
    created_at TIMESTAMP DEFAULT NOW(),

    UNIQUE(recorded_at, source, metric_type)
);

CREATE INDEX idx_health_metrics_date ON health.metrics(date DESC);
CREATE INDEX idx_health_metrics_type ON health.metrics(metric_type, date DESC);
CREATE INDEX idx_health_metrics_source ON health.metrics(source);

-- Metric type reference
CREATE TABLE health.metric_types (
    name VARCHAR(30) PRIMARY KEY,
    display_name VARCHAR(50),
    unit VARCHAR(10),
    category VARCHAR(20),  -- 'body', 'sleep', 'activity', 'heart'
    aggregation VARCHAR(10) DEFAULT 'avg'  -- 'avg', 'sum', 'last', 'min', 'max'
);

INSERT INTO health.metric_types (name, display_name, unit, category, aggregation) VALUES
    ('weight', 'Weight', 'kg', 'body', 'last'),
    ('body_fat', 'Body Fat %', '%', 'body', 'last'),
    ('muscle_mass', 'Muscle Mass', 'kg', 'body', 'last'),
    ('hrv', 'Heart Rate Variability', 'ms', 'heart', 'avg'),
    ('rhr', 'Resting Heart Rate', 'bpm', 'heart', 'avg'),
    ('recovery', 'Recovery Score', 'score', 'activity', 'last'),
    ('strain', 'Strain', 'score', 'activity', 'sum'),
    ('sleep_duration', 'Sleep Duration', 'hours', 'sleep', 'sum'),
    ('sleep_quality', 'Sleep Quality', 'score', 'sleep', 'last'),
    ('deep_sleep', 'Deep Sleep', 'hours', 'sleep', 'sum'),
    ('rem_sleep', 'REM Sleep', 'hours', 'sleep', 'sum'),
    ('steps', 'Steps', 'steps', 'activity', 'sum'),
    ('active_calories', 'Active Calories', 'kcal', 'activity', 'sum');

-- Workout sessions
CREATE TABLE health.workouts (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    started_at TIMESTAMP,
    ended_at TIMESTAMP,

    workout_type VARCHAR(50) NOT NULL,  -- 'strength', 'running', 'cycling', 'hiit', 'yoga', etc.
    name VARCHAR(100),                   -- 'Morning Run', 'Push Day', etc.

    duration_min INT,
    calories_burned INT,
    avg_hr INT,
    max_hr INT,
    strain DECIMAL(4,1),

    -- Strength specific
    exercises JSONB,  -- [{name, sets, reps, weight_kg}, ...]

    -- Cardio specific
    distance_km DECIMAL(6,2),
    pace_min_per_km DECIMAL(4,2),
    elevation_m INT,

    notes TEXT,
    source VARCHAR(30) DEFAULT 'manual',
    external_id VARCHAR(100),
    raw_data JSONB,

    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_workouts_date ON health.workouts(date DESC);
CREATE INDEX idx_workouts_type ON health.workouts(workout_type);

-- ============================================================================
-- NUTRITION SCHEMA: Ingredients, meals, food logging
-- ============================================================================

-- Master ingredient database
CREATE TABLE nutrition.ingredients (
    id SERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    brand VARCHAR(100),

    -- Nutrition per 100g
    calories_per_100g DECIMAL(6,1),
    protein_per_100g DECIMAL(5,1),
    carbs_per_100g DECIMAL(5,1),
    fat_per_100g DECIMAL(5,1),
    fiber_per_100g DECIMAL(5,1),
    sugar_per_100g DECIMAL(5,1),
    sodium_mg_per_100g DECIMAL(6,1),

    -- Common serving info
    serving_size_g DECIMAL(6,1),
    serving_label VARCHAR(50),  -- '1 cup', '1 medium', '1 slice'

    -- Categorization
    category VARCHAR(30),        -- 'protein', 'vegetable', 'fruit', 'grain', 'dairy', 'fat', 'other'
    subcategory VARCHAR(30),     -- 'poultry', 'leafy_green', 'citrus', etc.
    is_whole_food BOOLEAN DEFAULT TRUE,

    -- Identifiers
    barcode VARCHAR(50),
    usda_id VARCHAR(20),

    -- Meta
    verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_ingredients_name ON nutrition.ingredients(name);
CREATE INDEX idx_ingredients_category ON nutrition.ingredients(category);
CREATE INDEX idx_ingredients_barcode ON nutrition.ingredients(barcode);

-- Seed with common ingredients
INSERT INTO nutrition.ingredients (name, calories_per_100g, protein_per_100g, carbs_per_100g, fat_per_100g, fiber_per_100g, category, serving_size_g, serving_label, verified) VALUES
    ('Chicken Breast (raw)', 120, 22.5, 0, 2.6, 0, 'protein', 150, '1 breast', TRUE),
    ('Chicken Breast (cooked)', 165, 31, 0, 3.6, 0, 'protein', 140, '1 breast', TRUE),
    ('Salmon (raw)', 208, 20, 0, 13, 0, 'protein', 150, '1 fillet', TRUE),
    ('Eggs (whole)', 155, 13, 1.1, 11, 0, 'protein', 50, '1 large', TRUE),
    ('Egg Whites', 52, 11, 0.7, 0.2, 0, 'protein', 33, '1 large', TRUE),
    ('Ground Beef (90% lean)', 176, 20, 0, 10, 0, 'protein', 115, '4 oz', TRUE),
    ('White Rice (cooked)', 130, 2.7, 28, 0.3, 0.4, 'grain', 158, '1 cup', TRUE),
    ('Brown Rice (cooked)', 112, 2.6, 24, 0.9, 1.8, 'grain', 195, '1 cup', TRUE),
    ('Oats (dry)', 389, 17, 66, 7, 11, 'grain', 40, '1/2 cup', TRUE),
    ('Bread (whole wheat)', 247, 13, 41, 3.4, 7, 'grain', 28, '1 slice', TRUE),
    ('Broccoli', 34, 2.8, 7, 0.4, 2.6, 'vegetable', 91, '1 cup chopped', TRUE),
    ('Spinach (raw)', 23, 2.9, 3.6, 0.4, 2.2, 'vegetable', 30, '1 cup', TRUE),
    ('Sweet Potato', 86, 1.6, 20, 0.1, 3, 'vegetable', 130, '1 medium', TRUE),
    ('Banana', 89, 1.1, 23, 0.3, 2.6, 'fruit', 118, '1 medium', TRUE),
    ('Apple', 52, 0.3, 14, 0.2, 2.4, 'fruit', 182, '1 medium', TRUE),
    ('Avocado', 160, 2, 9, 15, 7, 'fat', 150, '1 medium', TRUE),
    ('Olive Oil', 884, 0, 0, 100, 0, 'fat', 14, '1 tbsp', TRUE),
    ('Greek Yogurt (plain, nonfat)', 59, 10, 3.6, 0.7, 0, 'dairy', 245, '1 cup', TRUE),
    ('Milk (whole)', 61, 3.2, 4.8, 3.3, 0, 'dairy', 244, '1 cup', TRUE),
    ('Almonds', 579, 21, 22, 50, 12.5, 'fat', 28, '1 oz', TRUE),
    ('Peanut Butter', 588, 25, 20, 50, 6, 'fat', 32, '2 tbsp', TRUE);

-- Meal templates (batch cooking)
CREATE TABLE nutrition.meals (
    id SERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    description TEXT,

    -- Batch info
    total_portions INT NOT NULL DEFAULT 1,
    portions_remaining INT,

    -- Calculated per-portion macros (computed from ingredients)
    calories_per_portion INT,
    protein_per_portion DECIMAL(5,1),
    carbs_per_portion DECIMAL(5,1),
    fat_per_portion DECIMAL(5,1),
    fiber_per_portion DECIMAL(5,1),

    -- Meal classification
    meal_type VARCHAR(20),       -- 'breakfast', 'lunch', 'dinner', 'snack', 'any'
    cuisine VARCHAR(30),         -- 'asian', 'mediterranean', 'mexican', etc.
    tags TEXT[],                 -- ['high-protein', 'meal-prep', 'quick']

    -- Batch tracking
    prep_date DATE,
    expiry_date DATE,
    storage_location VARCHAR(30),  -- 'fridge', 'freezer'

    -- Template vs instance
    is_template BOOLEAN DEFAULT FALSE,  -- Reusable recipes
    template_id INT REFERENCES nutrition.meals(id),  -- If this is an instance of a template

    -- Meta
    prep_time_min INT,
    cook_time_min INT,
    instructions TEXT,
    photo_url TEXT,
    source_url TEXT,

    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_meals_template ON nutrition.meals(is_template);
CREATE INDEX idx_meals_prep_date ON nutrition.meals(prep_date DESC);

-- Meal-ingredient junction
CREATE TABLE nutrition.meal_ingredients (
    id SERIAL PRIMARY KEY,
    meal_id INT NOT NULL REFERENCES nutrition.meals(id) ON DELETE CASCADE,
    ingredient_id INT REFERENCES nutrition.ingredients(id),

    quantity_g DECIMAL(7,1) NOT NULL,
    preparation VARCHAR(50),  -- 'raw', 'cooked', 'chopped', 'diced'

    -- For ingredients not yet in DB
    raw_text VARCHAR(200),
    estimated_calories INT,
    estimated_protein DECIMAL(5,1),
    estimated_carbs DECIMAL(5,1),
    estimated_fat DECIMAL(5,1),

    notes TEXT,

    UNIQUE(meal_id, ingredient_id)
);

-- Daily food log
CREATE TABLE nutrition.food_log (
    id SERIAL PRIMARY KEY,
    logged_at TIMESTAMP NOT NULL DEFAULT NOW(),
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    meal_time VARCHAR(20),  -- 'breakfast', 'lunch', 'dinner', 'snack'
    time_of_day TIME,

    -- Option 1: Log from meal template
    meal_id INT REFERENCES nutrition.meals(id),
    portion_number INT,      -- 'serving 3 of 5'
    portion_size DECIMAL(3,2) DEFAULT 1.0,  -- Can be 0.5 for half portion, 1.5 for large

    -- Option 2: Log single ingredient
    ingredient_id INT REFERENCES nutrition.ingredients(id),
    quantity_g DECIMAL(7,1),

    -- Calculated/stored macros at log time
    calories INT,
    protein_g DECIMAL(5,1),
    carbs_g DECIMAL(5,1),
    fat_g DECIMAL(5,1),
    fiber_g DECIMAL(5,1),

    -- Option 3: Quick/estimated entry
    description TEXT,
    confidence VARCHAR(10) DEFAULT 'high',  -- 'high', 'medium', 'low'

    -- Context
    location VARCHAR(30),    -- 'home', 'work', 'restaurant', 'travel'
    restaurant_name VARCHAR(100),

    -- Input method tracking
    source VARCHAR(20) DEFAULT 'manual',  -- 'manual', 'voice', 'photo', 'barcode', 'camera'
    photo_url TEXT,
    voice_transcript TEXT,

    -- Linking
    grocery_item_id INT,  -- Link to finance.grocery_items if applicable

    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_food_log_date ON nutrition.food_log(date DESC);
CREATE INDEX idx_food_log_meal_time ON nutrition.food_log(date, meal_time);

-- Water tracking
CREATE TABLE nutrition.water_log (
    id SERIAL PRIMARY KEY,
    logged_at TIMESTAMP NOT NULL DEFAULT NOW(),
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    amount_ml INT NOT NULL,
    source VARCHAR(20) DEFAULT 'manual',  -- 'manual', 'smart_bottle', 'voice'
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_water_log_date ON nutrition.water_log(date DESC);

-- ============================================================================
-- FINANCE SCHEMA: Transactions, groceries, budgets
-- ============================================================================

-- Bank accounts (for multi-account tracking)
CREATE TABLE finance.accounts (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    institution VARCHAR(100),
    account_type VARCHAR(30),  -- 'checking', 'savings', 'credit_card'
    last_four VARCHAR(4),
    plaid_account_id VARCHAR(100),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW()
);

-- All transactions
CREATE TABLE finance.transactions (
    id SERIAL PRIMARY KEY,
    external_id VARCHAR(100) UNIQUE,  -- Plaid transaction ID
    account_id INT REFERENCES finance.accounts(id),

    date DATE NOT NULL,
    posted_date DATE,

    merchant_name VARCHAR(200),
    merchant_name_clean VARCHAR(200),  -- Cleaned/normalized name

    amount DECIMAL(10,2) NOT NULL,     -- Positive = expense, negative = income
    currency VARCHAR(3) DEFAULT 'USD',

    -- Categorization
    plaid_category VARCHAR(100),       -- Original from Plaid
    plaid_category_id VARCHAR(50),
    category VARCHAR(50),              -- Your category
    subcategory VARCHAR(50),

    -- Food-specific flags
    is_grocery BOOLEAN DEFAULT FALSE,
    is_restaurant BOOLEAN DEFAULT FALSE,
    is_food_related BOOLEAN DEFAULT FALSE,

    -- For grocery transactions
    store_name VARCHAR(100),
    receipt_processed BOOLEAN DEFAULT FALSE,

    -- Meta
    notes TEXT,
    tags TEXT[],
    is_recurring BOOLEAN DEFAULT FALSE,
    is_hidden BOOLEAN DEFAULT FALSE,  -- For transfers, etc.

    raw_data JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_transactions_date ON finance.transactions(date DESC);
CREATE INDEX idx_transactions_category ON finance.transactions(category);
CREATE INDEX idx_transactions_merchant ON finance.transactions(merchant_name_clean);
CREATE INDEX idx_transactions_grocery ON finance.transactions(is_grocery) WHERE is_grocery = TRUE;

-- Grocery line items (from receipt processing)
CREATE TABLE finance.grocery_items (
    id SERIAL PRIMARY KEY,
    transaction_id INT REFERENCES finance.transactions(id) ON DELETE CASCADE,

    item_name VARCHAR(200) NOT NULL,
    item_name_clean VARCHAR(200),  -- Normalized

    quantity DECIMAL(6,2) DEFAULT 1,
    unit VARCHAR(20),              -- 'lb', 'oz', 'each', 'pack'
    unit_price DECIMAL(8,2),
    total_price DECIMAL(8,2) NOT NULL,

    -- Link to nutrition
    ingredient_id INT REFERENCES nutrition.ingredients(id),

    -- Categorization
    category VARCHAR(30),          -- 'produce', 'meat', 'dairy', 'pantry', 'frozen', 'other'
    is_healthy BOOLEAN,            -- Based on your health goals

    -- For price tracking
    price_per_unit DECIMAL(8,2),   -- Normalized price (per lb, per oz, etc.)

    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_grocery_items_transaction ON finance.grocery_items(transaction_id);
CREATE INDEX idx_grocery_items_ingredient ON finance.grocery_items(ingredient_id);

-- Merchant mapping (for auto-categorization)
CREATE TABLE finance.merchant_rules (
    id SERIAL PRIMARY KEY,
    merchant_pattern VARCHAR(200) NOT NULL,  -- Regex or LIKE pattern
    category VARCHAR(50) NOT NULL,
    subcategory VARCHAR(50),
    is_grocery BOOLEAN DEFAULT FALSE,
    is_restaurant BOOLEAN DEFAULT FALSE,
    is_food_related BOOLEAN DEFAULT FALSE,
    store_name VARCHAR(100),

    priority INT DEFAULT 0,  -- Higher = checked first
    created_at TIMESTAMP DEFAULT NOW()
);

-- Seed common merchant rules
INSERT INTO finance.merchant_rules (merchant_pattern, category, is_grocery, store_name, priority) VALUES
    ('%WHOLE FOODS%', 'grocery', TRUE, 'Whole Foods', 10),
    ('%TRADER JOE%', 'grocery', TRUE, 'Trader Joes', 10),
    ('%COSTCO%', 'grocery', TRUE, 'Costco', 10),
    ('%WALMART%', 'grocery', TRUE, 'Walmart', 5),
    ('%TARGET%', 'grocery', TRUE, 'Target', 5),
    ('%SAFEWAY%', 'grocery', TRUE, 'Safeway', 10),
    ('%KROGER%', 'grocery', TRUE, 'Kroger', 10),
    ('%ALDI%', 'grocery', TRUE, 'Aldi', 10),
    ('%PUBLIX%', 'grocery', TRUE, 'Publix', 10),
    ('%SPROUTS%', 'grocery', TRUE, 'Sprouts', 10),
    ('%AMAZON FRESH%', 'grocery', TRUE, 'Amazon Fresh', 10),
    ('%INSTACART%', 'grocery', TRUE, 'Instacart', 10);

INSERT INTO finance.merchant_rules (merchant_pattern, category, is_restaurant, is_food_related, priority) VALUES
    ('%DOORDASH%', 'food_delivery', TRUE, TRUE, 10),
    ('%UBER EATS%', 'food_delivery', TRUE, TRUE, 10),
    ('%GRUBHUB%', 'food_delivery', TRUE, TRUE, 10),
    ('%STARBUCKS%', 'restaurant', TRUE, TRUE, 10),
    ('%CHIPOTLE%', 'restaurant', TRUE, TRUE, 10),
    ('%MCDONALD%', 'restaurant', TRUE, TRUE, 10);

-- Monthly budgets
CREATE TABLE finance.budgets (
    id SERIAL PRIMARY KEY,
    month DATE NOT NULL,  -- First day of month
    category VARCHAR(50) NOT NULL,
    budget_amount DECIMAL(10,2) NOT NULL,

    UNIQUE(month, category)
);

-- ============================================================================
-- NOTES SCHEMA: Metadata index for Obsidian notes
-- ============================================================================

CREATE TABLE notes.entries (
    id SERIAL PRIMARY KEY,
    file_path VARCHAR(500) UNIQUE NOT NULL,
    title VARCHAR(300),

    note_type VARCHAR(30),  -- 'daily', 'meeting', 'idea', 'project', 'review', 'recipe', 'workout'

    -- Dates
    created_at TIMESTAMP,
    modified_at TIMESTAMP,
    linked_date DATE,  -- For daily notes

    -- Content metadata
    tags TEXT[],
    links_to TEXT[],      -- Other notes this links to
    linked_from TEXT[],   -- Notes that link to this

    -- AI-generated
    summary TEXT,
    key_points TEXT[],
    action_items TEXT[],

    -- Search
    word_count INT,

    indexed_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_notes_type ON notes.entries(note_type);
CREATE INDEX idx_notes_date ON notes.entries(linked_date DESC);
CREATE INDEX idx_notes_tags ON notes.entries USING GIN(tags);
CREATE INDEX idx_notes_modified ON notes.entries(modified_at DESC);

-- ============================================================================
-- HOME SCHEMA: Home Assistant relevant data (aggregated, not raw)
-- ============================================================================

-- Device states that matter for life tracking
CREATE TABLE home.device_snapshots (
    id SERIAL PRIMARY KEY,
    recorded_at TIMESTAMP NOT NULL DEFAULT NOW(),
    date DATE NOT NULL DEFAULT CURRENT_DATE,

    entity_id VARCHAR(100) NOT NULL,
    friendly_name VARCHAR(100),
    state VARCHAR(100),
    attributes JSONB,

    category VARCHAR(30)  -- 'scale', 'sleep', 'environment', 'kitchen'
);

CREATE INDEX idx_device_snapshots_date ON home.device_snapshots(date DESC);
CREATE INDEX idx_device_snapshots_entity ON home.device_snapshots(entity_id, date DESC);

-- Kitchen activity detection (for your camera idea)
CREATE TABLE home.kitchen_events (
    id SERIAL PRIMARY KEY,
    detected_at TIMESTAMP NOT NULL DEFAULT NOW(),
    date DATE NOT NULL DEFAULT CURRENT_DATE,

    event_type VARCHAR(30) NOT NULL,  -- 'cooking_started', 'cooking_ended', 'person_detected'
    duration_min INT,

    -- AI detection results
    detected_items TEXT[],  -- What the camera detected
    confidence DECIMAL(3,2),

    -- Linking
    food_log_id INT REFERENCES nutrition.food_log(id),
    meal_id INT REFERENCES nutrition.meals(id),

    prompted_user BOOLEAN DEFAULT FALSE,  -- Did we ask user to log?
    user_responded BOOLEAN DEFAULT FALSE,

    raw_data JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_kitchen_events_date ON home.kitchen_events(date DESC);

-- ============================================================================
-- FUNCTIONS: Useful computed values
-- ============================================================================

-- Function to calculate daily nutrition totals
CREATE OR REPLACE FUNCTION nutrition.get_daily_totals(target_date DATE)
RETURNS TABLE (
    calories INT,
    protein_g DECIMAL(5,1),
    carbs_g DECIMAL(5,1),
    fat_g DECIMAL(5,1),
    fiber_g DECIMAL(5,1),
    meals_logged BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE(SUM(fl.calories), 0)::INT,
        COALESCE(SUM(fl.protein_g), 0)::DECIMAL(5,1),
        COALESCE(SUM(fl.carbs_g), 0)::DECIMAL(5,1),
        COALESCE(SUM(fl.fat_g), 0)::DECIMAL(5,1),
        COALESCE(SUM(fl.fiber_g), 0)::DECIMAL(5,1),
        COUNT(*)
    FROM nutrition.food_log fl
    WHERE fl.date = target_date;
END;
$$ LANGUAGE plpgsql;

-- Function to recalculate meal macros from ingredients
CREATE OR REPLACE FUNCTION nutrition.recalculate_meal_macros(p_meal_id INT)
RETURNS VOID AS $$
DECLARE
    total_calories DECIMAL;
    total_protein DECIMAL;
    total_carbs DECIMAL;
    total_fat DECIMAL;
    total_fiber DECIMAL;
    portions INT;
BEGIN
    SELECT m.total_portions INTO portions FROM nutrition.meals m WHERE m.id = p_meal_id;

    SELECT
        COALESCE(SUM(
            CASE WHEN mi.ingredient_id IS NOT NULL
            THEN (i.calories_per_100g * mi.quantity_g / 100)
            ELSE mi.estimated_calories END
        ), 0),
        COALESCE(SUM(
            CASE WHEN mi.ingredient_id IS NOT NULL
            THEN (i.protein_per_100g * mi.quantity_g / 100)
            ELSE mi.estimated_protein END
        ), 0),
        COALESCE(SUM(
            CASE WHEN mi.ingredient_id IS NOT NULL
            THEN (i.carbs_per_100g * mi.quantity_g / 100)
            ELSE mi.estimated_carbs END
        ), 0),
        COALESCE(SUM(
            CASE WHEN mi.ingredient_id IS NOT NULL
            THEN (i.fat_per_100g * mi.quantity_g / 100)
            ELSE mi.estimated_fat END
        ), 0),
        COALESCE(SUM(
            CASE WHEN mi.ingredient_id IS NOT NULL
            THEN (i.fiber_per_100g * mi.quantity_g / 100)
            ELSE 0 END
        ), 0)
    INTO total_calories, total_protein, total_carbs, total_fat, total_fiber
    FROM nutrition.meal_ingredients mi
    LEFT JOIN nutrition.ingredients i ON mi.ingredient_id = i.id
    WHERE mi.meal_id = p_meal_id;

    UPDATE nutrition.meals SET
        calories_per_portion = (total_calories / portions)::INT,
        protein_per_portion = total_protein / portions,
        carbs_per_portion = total_carbs / portions,
        fat_per_portion = total_fat / portions,
        fiber_per_portion = total_fiber / portions,
        updated_at = NOW()
    WHERE id = p_meal_id;
END;
$$ LANGUAGE plpgsql;

-- Function to update daily summary
CREATE OR REPLACE FUNCTION core.update_daily_summary(target_date DATE)
RETURNS VOID AS $$
BEGIN
    INSERT INTO core.daily_summary (
        date,
        weight_kg, recovery_score, hrv_avg, rhr_avg, sleep_hours, strain, steps, active_calories,
        calories_consumed, protein_g, carbs_g, fat_g, fiber_g, meals_logged,
        total_spent, grocery_spent, eating_out_spent,
        workouts_count,
        updated_at
    )
    SELECT
        target_date,
        -- Health
        (SELECT value FROM health.metrics WHERE date = target_date AND metric_type = 'weight' ORDER BY recorded_at DESC LIMIT 1),
        (SELECT value::INT FROM health.metrics WHERE date = target_date AND metric_type = 'recovery' ORDER BY recorded_at DESC LIMIT 1),
        (SELECT AVG(value)::INT FROM health.metrics WHERE date = target_date AND metric_type = 'hrv'),
        (SELECT AVG(value)::INT FROM health.metrics WHERE date = target_date AND metric_type = 'rhr'),
        (SELECT SUM(value) FROM health.metrics WHERE date = target_date AND metric_type = 'sleep_duration'),
        (SELECT SUM(value) FROM health.metrics WHERE date = target_date AND metric_type = 'strain'),
        (SELECT SUM(value)::INT FROM health.metrics WHERE date = target_date AND metric_type = 'steps'),
        (SELECT SUM(value)::INT FROM health.metrics WHERE date = target_date AND metric_type = 'active_calories'),
        -- Nutrition
        (SELECT SUM(calories)::INT FROM nutrition.food_log WHERE date = target_date),
        (SELECT SUM(protein_g)::INT FROM nutrition.food_log WHERE date = target_date),
        (SELECT SUM(carbs_g)::INT FROM nutrition.food_log WHERE date = target_date),
        (SELECT SUM(fat_g)::INT FROM nutrition.food_log WHERE date = target_date),
        (SELECT SUM(fiber_g)::INT FROM nutrition.food_log WHERE date = target_date),
        (SELECT COUNT(*) FROM nutrition.food_log WHERE date = target_date),
        -- Finance
        (SELECT SUM(amount) FROM finance.transactions WHERE date = target_date AND amount > 0),
        (SELECT SUM(amount) FROM finance.transactions WHERE date = target_date AND is_grocery = TRUE),
        (SELECT SUM(amount) FROM finance.transactions WHERE date = target_date AND is_restaurant = TRUE),
        -- Activity
        (SELECT COUNT(*) FROM health.workouts WHERE date = target_date),
        NOW()
    ON CONFLICT (date) DO UPDATE SET
        weight_kg = EXCLUDED.weight_kg,
        recovery_score = EXCLUDED.recovery_score,
        hrv_avg = EXCLUDED.hrv_avg,
        rhr_avg = EXCLUDED.rhr_avg,
        sleep_hours = EXCLUDED.sleep_hours,
        strain = EXCLUDED.strain,
        steps = EXCLUDED.steps,
        active_calories = EXCLUDED.active_calories,
        calories_consumed = EXCLUDED.calories_consumed,
        protein_g = EXCLUDED.protein_g,
        carbs_g = EXCLUDED.carbs_g,
        fat_g = EXCLUDED.fat_g,
        fiber_g = EXCLUDED.fiber_g,
        meals_logged = EXCLUDED.meals_logged,
        total_spent = EXCLUDED.total_spent,
        grocery_spent = EXCLUDED.grocery_spent,
        eating_out_spent = EXCLUDED.eating_out_spent,
        workouts_count = EXCLUDED.workouts_count,
        updated_at = NOW();
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VIEWS: Commonly needed queries
-- ============================================================================

-- Weekly nutrition averages
CREATE VIEW nutrition.weekly_averages AS
SELECT
    DATE_TRUNC('week', date)::DATE as week_start,
    ROUND(AVG(calories_consumed)) as avg_calories,
    ROUND(AVG(protein_g)) as avg_protein,
    ROUND(AVG(carbs_g)) as avg_carbs,
    ROUND(AVG(fat_g)) as avg_fat,
    COUNT(*) as days_logged
FROM core.daily_summary
WHERE calories_consumed IS NOT NULL
GROUP BY DATE_TRUNC('week', date)
ORDER BY week_start DESC;

-- Health trends (7-day rolling average)
CREATE VIEW health.trends AS
SELECT
    date,
    weight_kg,
    AVG(weight_kg) OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) as weight_7d_avg,
    recovery_score,
    AVG(recovery_score) OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) as recovery_7d_avg,
    hrv_avg,
    AVG(hrv_avg) OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) as hrv_7d_avg
FROM core.daily_summary
WHERE date >= CURRENT_DATE - INTERVAL '90 days'
ORDER BY date DESC;

-- Cost per macro (from groceries)
CREATE VIEW finance.cost_per_macro AS
SELECT
    gi.item_name_clean,
    gi.total_price,
    i.protein_per_100g,
    i.calories_per_100g,
    CASE WHEN i.protein_per_100g > 0
        THEN ROUND((gi.total_price / (i.protein_per_100g * gi.quantity / 100))::NUMERIC, 2)
        ELSE NULL
    END as cost_per_g_protein,
    CASE WHEN i.calories_per_100g > 0
        THEN ROUND((gi.total_price / (i.calories_per_100g * gi.quantity / 100) * 100)::NUMERIC, 2)
        ELSE NULL
    END as cost_per_100_cal
FROM finance.grocery_items gi
JOIN nutrition.ingredients i ON gi.ingredient_id = i.id
WHERE gi.total_price > 0;

-- ============================================================================
-- GRANTS: For n8n and other services
-- ============================================================================

-- Create a read-write role for n8n
-- (Uncomment and adjust password when setting up)
-- CREATE ROLE n8n_user WITH LOGIN PASSWORD 'change_me';
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA core, health, nutrition, finance, notes, home TO n8n_user;
-- GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA core, health, nutrition, finance, notes, home TO n8n_user;
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA core, health, nutrition, finance, notes, home TO n8n_user;

-- Create a read-only role for dashboards
-- CREATE ROLE dashboard_reader WITH LOGIN PASSWORD 'change_me';
-- GRANT USAGE ON SCHEMA core, health, nutrition, finance, notes, home TO dashboard_reader;
-- GRANT SELECT ON ALL TABLES IN SCHEMA core, health, nutrition, finance, notes, home TO dashboard_reader;

COMMENT ON SCHEMA core IS 'Shared reference data and daily summaries';
COMMENT ON SCHEMA health IS 'Biometrics, sleep, workouts from Whoop/scale/Apple Health';
COMMENT ON SCHEMA nutrition IS 'Food logging, meal prep, ingredients database';
COMMENT ON SCHEMA finance IS 'Bank transactions, grocery tracking, budgets';
COMMENT ON SCHEMA notes IS 'Metadata index for Obsidian notes';
COMMENT ON SCHEMA home IS 'Home Assistant relevant aggregates and kitchen detection';

-- Done!
SELECT 'Nexus database initialized successfully!' as status;
