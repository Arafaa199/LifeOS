-- ============================================================================
-- NEXUS: Extended Schema
-- Additional tables for comprehensive life tracking
-- Run AFTER init.sql or add to init.sql
-- ============================================================================

-- ============================================================================
-- CORE SCHEMA EXTENSIONS
-- ============================================================================

-- Goals and targets with timelines
CREATE TABLE IF NOT EXISTS core.goals (
    id SERIAL PRIMARY KEY,
    category VARCHAR(30) NOT NULL,  -- 'weight', 'nutrition', 'fitness', 'finance', 'habit'
    name VARCHAR(100) NOT NULL,
    description TEXT,

    -- Target values
    target_value DECIMAL(10,2),
    target_unit VARCHAR(20),
    current_value DECIMAL(10,2),
    starting_value DECIMAL(10,2),

    -- Timeline
    start_date DATE NOT NULL DEFAULT CURRENT_DATE,
    target_date DATE,

    -- Status
    status VARCHAR(20) DEFAULT 'active',  -- 'active', 'achieved', 'paused', 'abandoned'
    achieved_date DATE,

    -- Tracking
    check_frequency VARCHAR(20) DEFAULT 'daily',  -- 'daily', 'weekly', 'monthly'
    reminder_enabled BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Daily subjective tracking (mood, energy, stress)
CREATE TABLE IF NOT EXISTS core.daily_journal (
    date DATE PRIMARY KEY,

    -- Subjective ratings (1-10 scale)
    mood_score INT CHECK (mood_score BETWEEN 1 AND 10),
    energy_score INT CHECK (energy_score BETWEEN 1 AND 10),
    stress_score INT CHECK (stress_score BETWEEN 1 AND 10),
    motivation_score INT CHECK (motivation_score BETWEEN 1 AND 10),

    -- Qualitative
    mood_tags TEXT[],  -- ['happy', 'anxious', 'focused', 'tired']

    -- Notes
    morning_note TEXT,
    evening_note TEXT,
    gratitude TEXT[],  -- Array of gratitude items
    wins TEXT[],       -- What went well
    improvements TEXT[], -- What could be better

    -- Sleep subjective (complements Whoop data)
    sleep_quality_subjective INT CHECK (sleep_quality_subjective BETWEEN 1 AND 10),
    sleep_notes TEXT,

    -- Habits completed
    habits_completed TEXT[],  -- ['meditation', 'exercise', 'reading']

    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Claude-generated insights and correlations
CREATE TABLE IF NOT EXISTS core.insights (
    id SERIAL PRIMARY KEY,
    generated_at TIMESTAMP NOT NULL DEFAULT NOW(),

    -- Classification
    insight_type VARCHAR(30) NOT NULL,  -- 'correlation', 'recommendation', 'anomaly', 'trend', 'prediction'
    category VARCHAR(30),               -- 'health', 'nutrition', 'finance', 'sleep', 'general'

    -- Content
    title VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    confidence DECIMAL(3,2),  -- 0.00 to 1.00

    -- Supporting data
    data_points JSONB,        -- The data that led to this insight
    date_range_start DATE,
    date_range_end DATE,

    -- Action
    actionable BOOLEAN DEFAULT FALSE,
    action_suggestion TEXT,
    action_taken BOOLEAN DEFAULT FALSE,
    action_taken_at TIMESTAMP,

    -- Feedback
    user_rating INT CHECK (user_rating BETWEEN 1 AND 5),  -- Was this helpful?
    user_feedback TEXT,

    -- Status
    is_dismissed BOOLEAN DEFAULT FALSE,
    is_pinned BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_insights_type ON core.insights(insight_type, generated_at DESC);
CREATE INDEX idx_insights_category ON core.insights(category, generated_at DESC);

-- ============================================================================
-- HEALTH SCHEMA EXTENSIONS
-- ============================================================================

-- Detailed Whoop data (beyond generic metrics)
CREATE TABLE IF NOT EXISTS health.whoop_sleep (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,

    -- Timing
    sleep_start TIMESTAMP,
    sleep_end TIMESTAMP,
    time_in_bed_min INT,

    -- Stages (minutes)
    awake_min INT,
    light_sleep_min INT,
    deep_sleep_min INT,
    rem_sleep_min INT,

    -- Quality metrics
    sleep_efficiency DECIMAL(4,1),  -- Percentage
    sleep_consistency INT,          -- Whoop consistency score
    sleep_performance INT,          -- Percentage of sleep needed
    sleep_needed_min INT,
    sleep_debt_min INT,

    -- Cycles
    cycles INT,                     -- Number of sleep cycles
    disturbances INT,

    -- Respiratory
    respiratory_rate DECIMAL(4,1),
    spo2_avg DECIMAL(4,1),

    -- Raw data
    raw_data JSONB,

    created_at TIMESTAMP DEFAULT NOW(),

    UNIQUE(date)
);

CREATE TABLE IF NOT EXISTS health.whoop_strain (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,

    -- Overall
    day_strain DECIMAL(4,1),
    max_hr INT,
    avg_hr INT,
    calories_total INT,
    calories_active INT,

    -- Activity breakdown
    activities JSONB,  -- Array of activities with strain, duration, type

    -- Raw data
    raw_data JSONB,

    created_at TIMESTAMP DEFAULT NOW(),

    UNIQUE(date)
);

CREATE TABLE IF NOT EXISTS health.whoop_recovery (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,

    -- Scores
    recovery_score INT,
    hrv_rmssd DECIMAL(6,2),
    rhr INT,
    spo2 DECIMAL(4,1),
    skin_temp DECIMAL(4,2),

    -- Factors
    sleep_performance INT,

    -- Whoop journal factors (if using journal)
    journal_factors JSONB,  -- {'alcohol': true, 'caffeine': false, 'stress': 2}

    -- Raw data
    raw_data JSONB,

    created_at TIMESTAMP DEFAULT NOW(),

    UNIQUE(date)
);

-- Body measurements beyond weight
CREATE TABLE IF NOT EXISTS health.body_measurements (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,

    -- Core measurements (cm)
    chest_cm DECIMAL(5,1),
    waist_cm DECIMAL(5,1),
    hips_cm DECIMAL(5,1),

    -- Arms (cm)
    left_arm_cm DECIMAL(5,1),
    right_arm_cm DECIMAL(5,1),

    -- Legs (cm)
    left_thigh_cm DECIMAL(5,1),
    right_thigh_cm DECIMAL(5,1),
    left_calf_cm DECIMAL(5,1),
    right_calf_cm DECIMAL(5,1),

    -- Other
    neck_cm DECIMAL(5,1),
    shoulders_cm DECIMAL(5,1),
    forearm_cm DECIMAL(5,1),

    -- Calculated
    waist_hip_ratio DECIMAL(4,3),

    -- Photo reference
    photo_front_url TEXT,
    photo_side_url TEXT,
    photo_back_url TEXT,

    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Supplements and medications
CREATE TABLE IF NOT EXISTS health.supplements (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    brand VARCHAR(100),

    -- Dosage
    dose_amount DECIMAL(8,2),
    dose_unit VARCHAR(20),
    frequency VARCHAR(30),  -- 'daily', 'twice_daily', 'as_needed'

    -- Timing
    time_of_day VARCHAR(20),  -- 'morning', 'evening', 'with_meals'

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    start_date DATE,
    end_date DATE,

    -- Info
    purpose TEXT,
    notes TEXT,

    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS health.supplement_log (
    id SERIAL PRIMARY KEY,
    supplement_id INT REFERENCES health.supplements(id),
    taken_at TIMESTAMP NOT NULL DEFAULT NOW(),
    date DATE NOT NULL DEFAULT CURRENT_DATE,

    dose_amount DECIMAL(8,2),  -- If different from default
    notes TEXT,

    created_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================================
-- NUTRITION SCHEMA EXTENSIONS
-- ============================================================================

-- Pantry inventory
CREATE TABLE IF NOT EXISTS nutrition.pantry (
    id SERIAL PRIMARY KEY,
    ingredient_id INT REFERENCES nutrition.ingredients(id),

    -- If not in ingredients table
    item_name VARCHAR(150),

    -- Quantity
    quantity DECIMAL(8,2),
    unit VARCHAR(20),

    -- Tracking
    purchase_date DATE,
    expiry_date DATE,
    opened_date DATE,

    -- Location
    storage_location VARCHAR(30),  -- 'fridge', 'freezer', 'pantry', 'spice_rack'

    -- Status
    is_staple BOOLEAN DEFAULT FALSE,  -- Auto-add to shopping list when low
    reorder_threshold DECIMAL(8,2),

    -- Linking
    grocery_item_id INT,  -- Link to purchase

    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Shopping lists
CREATE TABLE IF NOT EXISTS nutrition.shopping_lists (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    created_date DATE NOT NULL DEFAULT CURRENT_DATE,

    status VARCHAR(20) DEFAULT 'active',  -- 'active', 'completed', 'archived'
    completed_date DATE,

    -- Linked transaction when purchased
    transaction_id INT,

    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS nutrition.shopping_list_items (
    id SERIAL PRIMARY KEY,
    list_id INT REFERENCES nutrition.shopping_lists(id) ON DELETE CASCADE,

    ingredient_id INT REFERENCES nutrition.ingredients(id),
    item_name VARCHAR(150),  -- If not in ingredients

    quantity DECIMAL(8,2),
    unit VARCHAR(20),

    -- Categorization for store navigation
    category VARCHAR(30),  -- 'produce', 'meat', 'dairy', 'frozen', 'pantry'

    -- Status
    is_purchased BOOLEAN DEFAULT FALSE,
    actual_price DECIMAL(8,2),

    -- Source
    source VARCHAR(30),  -- 'manual', 'meal_plan', 'low_pantry', 'recipe'
    meal_id INT,  -- If from meal planning

    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Meal planning
CREATE TABLE IF NOT EXISTS nutrition.meal_plan (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    meal_time VARCHAR(20) NOT NULL,  -- 'breakfast', 'lunch', 'dinner', 'snack'

    -- What's planned
    meal_id INT REFERENCES nutrition.meals(id),
    recipe_notes TEXT,

    -- Status
    is_completed BOOLEAN DEFAULT FALSE,
    actual_food_log_id INT,  -- Link to what was actually eaten

    created_at TIMESTAMP DEFAULT NOW(),

    UNIQUE(date, meal_time)
);

-- ============================================================================
-- HOME SCHEMA EXTENSIONS
-- ============================================================================

-- Home Assistant device registry
CREATE TABLE IF NOT EXISTS home.devices (
    id SERIAL PRIMARY KEY,
    entity_id VARCHAR(150) UNIQUE NOT NULL,

    -- Device info
    friendly_name VARCHAR(150),
    device_class VARCHAR(50),
    domain VARCHAR(50),  -- 'sensor', 'binary_sensor', 'switch', 'light', etc.

    -- Categorization
    area VARCHAR(50),           -- 'bedroom', 'kitchen', 'office'
    nexus_category VARCHAR(30), -- 'health', 'environment', 'security', 'energy'

    -- Tracking config
    track_in_nexus BOOLEAN DEFAULT FALSE,
    track_frequency VARCHAR(20),  -- 'realtime', 'hourly', 'daily'

    -- Metadata
    manufacturer VARCHAR(100),
    model VARCHAR(100),
    integration VARCHAR(50),  -- 'whoop', 'tuya', 'hue', etc.

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    last_seen TIMESTAMP,

    attributes_schema JSONB,  -- Expected attributes structure

    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Home Assistant state history (selective, for tracked devices)
CREATE TABLE IF NOT EXISTS home.state_history (
    id SERIAL PRIMARY KEY,
    device_id INT REFERENCES home.devices(id),
    entity_id VARCHAR(150) NOT NULL,

    recorded_at TIMESTAMP NOT NULL,
    date DATE NOT NULL DEFAULT CURRENT_DATE,

    state VARCHAR(255),
    state_numeric DECIMAL(12,4),  -- Parsed numeric value if applicable

    attributes JSONB,

    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_state_history_device ON home.state_history(device_id, recorded_at DESC);
CREATE INDEX idx_state_history_date ON home.state_history(date DESC, entity_id);

-- Automation/event log
CREATE TABLE IF NOT EXISTS home.automation_log (
    id SERIAL PRIMARY KEY,
    triggered_at TIMESTAMP NOT NULL DEFAULT NOW(),

    automation_id VARCHAR(150),
    automation_name VARCHAR(200),

    trigger_entity VARCHAR(150),
    trigger_state VARCHAR(255),

    actions_executed JSONB,  -- What the automation did

    -- Context
    context_data JSONB,

    created_at TIMESTAMP DEFAULT NOW()
);

-- Environment snapshots (aggregated room conditions)
CREATE TABLE IF NOT EXISTS home.environment_log (
    id SERIAL PRIMARY KEY,
    recorded_at TIMESTAMP NOT NULL,
    date DATE NOT NULL DEFAULT CURRENT_DATE,

    area VARCHAR(50) NOT NULL,  -- 'bedroom', 'office', 'living_room'

    -- Conditions
    temperature_c DECIMAL(4,1),
    humidity_pct DECIMAL(4,1),
    co2_ppm INT,
    pm25 DECIMAL(5,1),
    light_lux INT,
    noise_db DECIMAL(4,1),

    -- Calculated
    air_quality_index INT,

    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_environment_date ON home.environment_log(date DESC, area);

-- ============================================================================
-- ACTIVITY/PRODUCTIVITY SCHEMA (NEW)
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS activity;

-- Time tracking / focus sessions
CREATE TABLE IF NOT EXISTS activity.focus_sessions (
    id SERIAL PRIMARY KEY,
    started_at TIMESTAMP NOT NULL,
    ended_at TIMESTAMP,
    date DATE NOT NULL DEFAULT CURRENT_DATE,

    -- What
    activity_type VARCHAR(30),  -- 'deep_work', 'meeting', 'admin', 'learning', 'creative'
    project VARCHAR(100),
    task VARCHAR(200),

    -- Duration
    planned_duration_min INT,
    actual_duration_min INT,

    -- Quality
    focus_rating INT CHECK (focus_rating BETWEEN 1 AND 10),
    interruptions INT DEFAULT 0,

    -- Technique
    technique VARCHAR(30),  -- 'pomodoro', 'timeblock', 'freeform'

    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Habit tracking
CREATE TABLE IF NOT EXISTS activity.habits (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,

    -- Schedule
    frequency VARCHAR(20) NOT NULL,  -- 'daily', 'weekdays', 'weekly', 'custom'
    target_days INT[],               -- [1,2,3,4,5] for weekdays (1=Monday)
    target_time TIME,

    -- Goal
    target_count INT DEFAULT 1,      -- How many times per occurrence
    unit VARCHAR(20),                -- 'minutes', 'times', 'pages', etc.

    -- Streak
    current_streak INT DEFAULT 0,
    longest_streak INT DEFAULT 0,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    start_date DATE,

    -- Categorization
    category VARCHAR(30),  -- 'health', 'productivity', 'learning', 'mindfulness'

    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS activity.habit_log (
    id SERIAL PRIMARY KEY,
    habit_id INT REFERENCES activity.habits(id),
    date DATE NOT NULL,

    completed BOOLEAN DEFAULT FALSE,
    count INT DEFAULT 0,             -- If habit has target_count > 1

    -- Quality
    difficulty INT CHECK (difficulty BETWEEN 1 AND 5),  -- How hard was it today

    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW(),

    UNIQUE(habit_id, date)
);

-- ============================================================================
-- VIEWS FOR EXTENDED SCHEMA
-- ============================================================================

-- Whoop daily overview
CREATE OR REPLACE VIEW health.whoop_daily AS
SELECT
    COALESCE(r.date, s.date, st.date) as date,
    r.recovery_score,
    r.hrv_rmssd as hrv,
    r.rhr,
    s.time_in_bed_min,
    s.deep_sleep_min + s.rem_sleep_min as quality_sleep_min,
    s.sleep_performance,
    st.day_strain as strain,
    st.calories_active
FROM health.whoop_recovery r
FULL OUTER JOIN health.whoop_sleep s ON r.date = s.date
FULL OUTER JOIN health.whoop_strain st ON r.date = st.date
ORDER BY date DESC;

-- Habit completion rates
CREATE OR REPLACE VIEW activity.habit_stats AS
SELECT
    h.id,
    h.name,
    h.category,
    h.current_streak,
    h.longest_streak,
    COUNT(hl.id) as total_entries,
    SUM(CASE WHEN hl.completed THEN 1 ELSE 0 END) as completed_count,
    ROUND(100.0 * SUM(CASE WHEN hl.completed THEN 1 ELSE 0 END) / NULLIF(COUNT(hl.id), 0), 1) as completion_rate
FROM activity.habits h
LEFT JOIN activity.habit_log hl ON h.id = hl.habit_id
WHERE h.is_active = TRUE
GROUP BY h.id, h.name, h.category, h.current_streak, h.longest_streak;

-- Pantry low stock alert
CREATE OR REPLACE VIEW nutrition.low_stock AS
SELECT
    p.id,
    COALESCE(i.name, p.item_name) as item_name,
    p.quantity,
    p.unit,
    p.reorder_threshold,
    p.storage_location,
    p.expiry_date,
    CASE WHEN p.expiry_date < CURRENT_DATE THEN 'expired'
         WHEN p.expiry_date < CURRENT_DATE + INTERVAL '3 days' THEN 'expiring_soon'
         WHEN p.quantity <= p.reorder_threshold THEN 'low_stock'
         ELSE 'ok' END as status
FROM nutrition.pantry p
LEFT JOIN nutrition.ingredients i ON p.ingredient_id = i.id
WHERE p.is_staple = TRUE
  AND (p.quantity <= p.reorder_threshold OR p.expiry_date < CURRENT_DATE + INTERVAL '7 days');

-- ============================================================================
-- UPDATE DAILY SUMMARY FUNCTION (Extended)
-- ============================================================================

CREATE OR REPLACE FUNCTION core.update_daily_summary_extended(target_date DATE)
RETURNS VOID AS $$
BEGIN
    -- First run the base update
    PERFORM core.update_daily_summary(target_date);

    -- Then add extended data
    UPDATE core.daily_summary SET
        -- Add subjective scores if available
        updated_at = NOW()
    WHERE date = target_date;

    -- Could add more extended aggregations here
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- SEED DATA FOR EXTENDED TABLES
-- ============================================================================

-- Default habits
INSERT INTO activity.habits (name, frequency, target_days, category, target_count, unit) VALUES
    ('Morning Meditation', 'daily', ARRAY[1,2,3,4,5,6,7], 'mindfulness', 1, 'session'),
    ('Exercise', 'daily', ARRAY[1,2,3,4,5,6,7], 'health', 1, 'session'),
    ('Read', 'daily', ARRAY[1,2,3,4,5,6,7], 'learning', 30, 'minutes'),
    ('Drink Water', 'daily', ARRAY[1,2,3,4,5,6,7], 'health', 8, 'glasses'),
    ('Journal', 'daily', ARRAY[1,2,3,4,5,6,7], 'mindfulness', 1, 'entry'),
    ('No Alcohol', 'daily', ARRAY[1,2,3,4,5,6,7], 'health', 1, 'day'),
    ('Sleep by 11pm', 'daily', ARRAY[1,2,3,4,5], 'health', 1, 'night')
ON CONFLICT DO NOTHING;

-- Sample HA devices to track
INSERT INTO home.devices (entity_id, friendly_name, domain, nexus_category, track_in_nexus, integration) VALUES
    ('sensor.whoop_recovery', 'Whoop Recovery', 'sensor', 'health', TRUE, 'whoop'),
    ('sensor.whoop_hrv', 'Whoop HRV', 'sensor', 'health', TRUE, 'whoop'),
    ('sensor.whoop_strain', 'Whoop Strain', 'sensor', 'health', TRUE, 'whoop'),
    ('sensor.smart_scale_weight', 'Smart Scale Weight', 'sensor', 'health', TRUE, 'scale'),
    ('sensor.bedroom_temperature', 'Bedroom Temperature', 'sensor', 'environment', TRUE, 'climate'),
    ('sensor.bedroom_humidity', 'Bedroom Humidity', 'sensor', 'environment', TRUE, 'climate')
ON CONFLICT (entity_id) DO NOTHING;

-- ============================================================================
-- PERFORMANCE INDEXES
-- ============================================================================

-- Composite indexes for common finance queries
CREATE INDEX IF NOT EXISTS idx_transactions_date_category_amount
ON finance.transactions(date DESC, category, amount);

CREATE INDEX IF NOT EXISTS idx_transactions_merchant_date
ON finance.transactions(merchant_name, date DESC);

-- Partial indexes for filtered queries (expenses vs income)
CREATE INDEX IF NOT EXISTS idx_transactions_expenses
ON finance.transactions(date DESC, amount) WHERE amount < 0;

CREATE INDEX IF NOT EXISTS idx_transactions_income
ON finance.transactions(date DESC, amount) WHERE amount > 0;

SELECT 'Extended schema initialized successfully!' as status;
