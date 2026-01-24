-- Migration: 004_create_normalized_schema
-- Purpose: Create normalized.* schema for cleaned/deduplicated data
-- Part of Phase 1: Data Pipeline Architecture
--
-- Rules:
-- - Idempotent: Re-processing raw data produces identical result
-- - Source traceability via raw_id foreign key
-- - Cleaned values (nulls handled, units standardized)
-- - Unique constraints on natural keys
-- - UPDATE allowed (for corrections), DELETE discouraged

BEGIN;

-- Create the normalized schema
CREATE SCHEMA IF NOT EXISTS normalized;

COMMENT ON SCHEMA normalized IS 'Cleaned, deduplicated data. One row per logical entity. Idempotent upserts.';

-- =============================================================================
-- normalized.daily_recovery - One row per day with WHOOP recovery data
-- =============================================================================
CREATE TABLE normalized.daily_recovery (
    date DATE PRIMARY KEY,

    -- Recovery metrics
    recovery_score INT,
    hrv DECIMAL(5,1),
    rhr INT,
    spo2 DECIMAL(4,1),
    skin_temp_c DECIMAL(4,2),

    -- Source tracking
    raw_id BIGINT REFERENCES raw.whoop_cycles(id),
    source VARCHAR(50) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_normalized_recovery_updated ON normalized.daily_recovery(updated_at DESC);

COMMENT ON TABLE normalized.daily_recovery IS 'Daily WHOOP recovery metrics. One row per day, latest data wins.';
COMMENT ON COLUMN normalized.daily_recovery.raw_id IS 'Reference to source row in raw.whoop_cycles';
COMMENT ON COLUMN normalized.daily_recovery.source IS 'Data source: home_assistant, manual, etc.';

-- =============================================================================
-- normalized.daily_sleep - One row per day with sleep data
-- =============================================================================
CREATE TABLE normalized.daily_sleep (
    date DATE PRIMARY KEY,

    -- Timing
    sleep_start TIMESTAMPTZ,
    sleep_end TIMESTAMPTZ,

    -- Duration (in minutes, standardized)
    total_sleep_min INT,
    time_in_bed_min INT,
    light_sleep_min INT,
    deep_sleep_min INT,
    rem_sleep_min INT,
    awake_min INT,

    -- Quality
    sleep_efficiency DECIMAL(5,2),
    sleep_performance INT,
    respiratory_rate DECIMAL(4,1),

    -- Source tracking
    raw_id BIGINT REFERENCES raw.whoop_sleep(id),
    source VARCHAR(50) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_normalized_sleep_updated ON normalized.daily_sleep(updated_at DESC);

COMMENT ON TABLE normalized.daily_sleep IS 'Daily sleep metrics. One row per day, latest data wins.';
COMMENT ON COLUMN normalized.daily_sleep.total_sleep_min IS 'Total sleep time in minutes (excluding awake time)';
COMMENT ON COLUMN normalized.daily_sleep.time_in_bed_min IS 'Total time in bed in minutes (including awake time)';

-- =============================================================================
-- normalized.daily_strain - One row per day with strain data
-- =============================================================================
CREATE TABLE normalized.daily_strain (
    date DATE PRIMARY KEY,

    day_strain DECIMAL(4,1),
    calories_burned INT,
    workout_count INT,
    average_hr INT,
    max_hr INT,

    -- Source tracking
    raw_id BIGINT REFERENCES raw.whoop_strain(id),
    source VARCHAR(50) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_normalized_strain_updated ON normalized.daily_strain(updated_at DESC);

COMMENT ON TABLE normalized.daily_strain IS 'Daily WHOOP strain metrics. One row per day, latest data wins.';
COMMENT ON COLUMN normalized.daily_strain.calories_burned IS 'Total calories burned (converted from kilojoules)';

-- =============================================================================
-- normalized.body_metrics - Body composition metrics (multiple per day allowed)
-- =============================================================================
CREATE TABLE normalized.body_metrics (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL,

    metric_type VARCHAR(30) NOT NULL,      -- 'weight', 'body_fat', 'muscle_mass', 'bmi'
    value DECIMAL(10,4) NOT NULL,
    unit VARCHAR(10) NOT NULL,             -- Standardized: 'kg', '%', 'kg/m2'

    -- Source tracking
    raw_id BIGINT REFERENCES raw.healthkit_samples(id),
    source VARCHAR(50) NOT NULL,
    source_device VARCHAR(100),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- One measurement per type per timestamp (idempotent)
    UNIQUE(date, metric_type, recorded_at)
);

CREATE INDEX idx_normalized_body_date ON normalized.body_metrics(date DESC);
CREATE INDEX idx_normalized_body_type ON normalized.body_metrics(metric_type, date DESC);
CREATE INDEX idx_normalized_body_updated ON normalized.body_metrics(updated_at DESC);

COMMENT ON TABLE normalized.body_metrics IS 'Body metrics from HealthKit (Eufy scale, etc.). Multiple per day allowed.';
COMMENT ON COLUMN normalized.body_metrics.metric_type IS 'Type: weight, body_fat, muscle_mass, bmi';
COMMENT ON COLUMN normalized.body_metrics.unit IS 'Standardized unit: kg for weight, % for body_fat';

-- =============================================================================
-- normalized.transactions - Parsed and categorized financial transactions
-- =============================================================================
CREATE TABLE normalized.transactions (
    id SERIAL PRIMARY KEY,

    -- Timing
    transaction_at TIMESTAMPTZ NOT NULL,
    date DATE NOT NULL,

    -- Core fields
    merchant_name VARCHAR(200),
    merchant_clean VARCHAR(200),
    amount DECIMAL(12,2) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'AED',

    -- Categorization
    category VARCHAR(50),
    subcategory VARCHAR(50),
    is_grocery BOOLEAN DEFAULT FALSE,
    is_restaurant BOOLEAN DEFAULT FALSE,
    is_food_related BOOLEAN DEFAULT FALSE,

    -- Bank details
    bank VARCHAR(50),
    card_last_four VARCHAR(4),
    balance_after DECIMAL(12,2),

    -- Flags
    is_recurring BOOLEAN DEFAULT FALSE,
    is_internal_transfer BOOLEAN DEFAULT FALSE,
    is_income BOOLEAN DEFAULT FALSE,

    -- Source tracking
    raw_id BIGINT REFERENCES raw.bank_sms(id),
    external_id VARCHAR(100) UNIQUE,       -- Dedup key (hash of sender|amount|merchant|date)
    source VARCHAR(50) NOT NULL,

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_normalized_txn_date ON normalized.transactions(date DESC);
CREATE INDEX idx_normalized_txn_category ON normalized.transactions(category, date DESC);
CREATE INDEX idx_normalized_txn_updated ON normalized.transactions(updated_at DESC);
CREATE INDEX idx_normalized_txn_is_income ON normalized.transactions(is_income, date DESC) WHERE is_income = TRUE;

COMMENT ON TABLE normalized.transactions IS 'Parsed bank transactions from SMS. Deduplicated by external_id.';
COMMENT ON COLUMN normalized.transactions.external_id IS 'SHA256 hash of sender|amount|merchant|date for deduplication';
COMMENT ON COLUMN normalized.transactions.merchant_clean IS 'Normalized merchant name after cleanup rules';

-- =============================================================================
-- normalized.food_log - Normalized food entries with calculated macros
-- =============================================================================
CREATE TABLE normalized.food_log (
    id SERIAL PRIMARY KEY,

    logged_at TIMESTAMPTZ NOT NULL,
    date DATE NOT NULL,
    meal_time VARCHAR(20),                 -- 'breakfast', 'lunch', 'dinner', 'snack'

    -- Food details
    description TEXT NOT NULL,
    calories INT,
    protein_g DECIMAL(5,1),
    carbs_g DECIMAL(5,1),
    fat_g DECIMAL(5,1),
    fiber_g DECIMAL(5,1),

    -- Context
    confidence VARCHAR(10) DEFAULT 'medium',  -- 'low', 'medium', 'high'
    location VARCHAR(30),                     -- 'home', 'restaurant', 'work'
    input_method VARCHAR(30),                 -- 'manual', 'voice', 'photo', 'shortcut'

    -- Source tracking
    raw_id BIGINT REFERENCES raw.manual_entries(id),
    source VARCHAR(50) NOT NULL,

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_normalized_food_date ON normalized.food_log(date DESC);
CREATE INDEX idx_normalized_food_meal ON normalized.food_log(date DESC, meal_time);
CREATE INDEX idx_normalized_food_updated ON normalized.food_log(updated_at DESC);

COMMENT ON TABLE normalized.food_log IS 'Food entries with macro data. Linked to raw.manual_entries.';
COMMENT ON COLUMN normalized.food_log.confidence IS 'Confidence level of calorie/macro estimates: low, medium, high';

-- =============================================================================
-- normalized.water_log - Water intake entries
-- =============================================================================
CREATE TABLE normalized.water_log (
    id SERIAL PRIMARY KEY,

    logged_at TIMESTAMPTZ NOT NULL,
    date DATE NOT NULL,
    amount_ml INT NOT NULL,

    -- Source tracking
    raw_id BIGINT REFERENCES raw.manual_entries(id),
    source VARCHAR(50) NOT NULL,

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_normalized_water_date ON normalized.water_log(date DESC);
CREATE INDEX idx_normalized_water_updated ON normalized.water_log(updated_at DESC);

COMMENT ON TABLE normalized.water_log IS 'Water intake entries in milliliters.';

-- =============================================================================
-- normalized.mood_log - Mood/energy entries
-- =============================================================================
CREATE TABLE normalized.mood_log (
    id SERIAL PRIMARY KEY,

    logged_at TIMESTAMPTZ NOT NULL,
    date DATE NOT NULL,

    -- Mood metrics (1-10 scale)
    mood_score INT CHECK (mood_score >= 1 AND mood_score <= 10),
    energy_score INT CHECK (energy_score >= 1 AND energy_score <= 10),
    stress_score INT CHECK (stress_score >= 1 AND stress_score <= 10),

    -- Optional notes
    notes TEXT,

    -- Source tracking
    raw_id BIGINT REFERENCES raw.manual_entries(id),
    source VARCHAR(50) NOT NULL,

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_normalized_mood_date ON normalized.mood_log(date DESC);
CREATE INDEX idx_normalized_mood_updated ON normalized.mood_log(updated_at DESC);

COMMENT ON TABLE normalized.mood_log IS 'Mood and energy tracking entries. Scores on 1-10 scale.';

-- =============================================================================
-- Helper function for updating updated_at timestamp
-- =============================================================================
CREATE OR REPLACE FUNCTION normalized.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION normalized.update_updated_at() IS 'Trigger function to auto-update updated_at on row modification';

-- Apply updated_at triggers to all normalized tables
CREATE TRIGGER set_updated_at_daily_recovery
    BEFORE UPDATE ON normalized.daily_recovery
    FOR EACH ROW EXECUTE FUNCTION normalized.update_updated_at();

CREATE TRIGGER set_updated_at_daily_sleep
    BEFORE UPDATE ON normalized.daily_sleep
    FOR EACH ROW EXECUTE FUNCTION normalized.update_updated_at();

CREATE TRIGGER set_updated_at_daily_strain
    BEFORE UPDATE ON normalized.daily_strain
    FOR EACH ROW EXECUTE FUNCTION normalized.update_updated_at();

CREATE TRIGGER set_updated_at_body_metrics
    BEFORE UPDATE ON normalized.body_metrics
    FOR EACH ROW EXECUTE FUNCTION normalized.update_updated_at();

CREATE TRIGGER set_updated_at_transactions
    BEFORE UPDATE ON normalized.transactions
    FOR EACH ROW EXECUTE FUNCTION normalized.update_updated_at();

CREATE TRIGGER set_updated_at_food_log
    BEFORE UPDATE ON normalized.food_log
    FOR EACH ROW EXECUTE FUNCTION normalized.update_updated_at();

CREATE TRIGGER set_updated_at_water_log
    BEFORE UPDATE ON normalized.water_log
    FOR EACH ROW EXECUTE FUNCTION normalized.update_updated_at();

CREATE TRIGGER set_updated_at_mood_log
    BEFORE UPDATE ON normalized.mood_log
    FOR EACH ROW EXECUTE FUNCTION normalized.update_updated_at();

COMMIT;
