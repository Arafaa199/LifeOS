-- Migration: 005_create_facts_schema
-- Purpose: Create facts.* schema for derived daily aggregates
-- Part of Phase 1: Data Pipeline Architecture
--
-- Rules:
-- - Derived only: Computed from normalized tables, never directly inserted
-- - Reproducible: Can be rebuilt from scratch at any time
-- - One row per date
-- - Used by dashboards and reporting
-- - Refreshed via functions that can be called on-demand or scheduled

BEGIN;

-- Create the facts schema
CREATE SCHEMA IF NOT EXISTS facts;

COMMENT ON SCHEMA facts IS 'Pre-computed daily aggregates derived from normalized tables. Fully reproducible.';

-- =============================================================================
-- facts.daily_health - Complete daily health summary
-- =============================================================================
CREATE TABLE facts.daily_health (
    date DATE PRIMARY KEY,

    -- Recovery (from normalized.daily_recovery)
    recovery_score INT,
    hrv DECIMAL(5,1),
    rhr INT,
    spo2 DECIMAL(4,1),
    skin_temp_c DECIMAL(4,2),

    -- Sleep (from normalized.daily_sleep)
    sleep_hours DECIMAL(4,2),
    sleep_quality INT,                      -- sleep_performance
    deep_sleep_hours DECIMAL(4,2),
    rem_sleep_hours DECIMAL(4,2),
    light_sleep_hours DECIMAL(4,2),
    time_in_bed_hours DECIMAL(4,2),
    sleep_efficiency DECIMAL(5,2),

    -- Strain (from normalized.daily_strain)
    day_strain DECIMAL(4,1),
    calories_burned INT,
    workout_count INT,
    average_hr INT,
    max_hr INT,

    -- Body (from normalized.body_metrics, latest per day)
    weight_kg DECIMAL(5,2),
    body_fat_pct DECIMAL(4,1),

    -- Mood (from normalized.mood_log, average per day)
    mood_score DECIMAL(3,1),
    energy_score DECIMAL(3,1),
    stress_score DECIMAL(3,1),

    -- Computed
    data_completeness DECIMAL(3,2),         -- 0.00 to 1.00

    -- Refresh tracking
    refreshed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_facts_health_refreshed ON facts.daily_health(refreshed_at DESC);

COMMENT ON TABLE facts.daily_health IS 'Daily health summary aggregating recovery, sleep, strain, body metrics, and mood.';
COMMENT ON COLUMN facts.daily_health.data_completeness IS 'Fraction of expected data present (0.00-1.00)';
COMMENT ON COLUMN facts.daily_health.sleep_hours IS 'Total sleep time in hours (excluding awake time)';

-- =============================================================================
-- facts.daily_nutrition - Daily nutrition summary
-- =============================================================================
CREATE TABLE facts.daily_nutrition (
    date DATE PRIMARY KEY,

    -- Totals (from normalized.food_log)
    calories INT,
    protein_g INT,
    carbs_g INT,
    fat_g INT,
    fiber_g INT,

    -- Counts
    meals_logged INT,
    entries_logged INT,

    -- Water (from normalized.water_log)
    water_ml INT,

    -- Quality assessment
    avg_confidence VARCHAR(10),             -- 'low', 'medium', 'high'
    has_all_meals BOOLEAN DEFAULT FALSE,    -- breakfast, lunch, dinner logged

    -- Refresh tracking
    refreshed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_facts_nutrition_refreshed ON facts.daily_nutrition(refreshed_at DESC);

COMMENT ON TABLE facts.daily_nutrition IS 'Daily nutrition totals from food and water logs.';
COMMENT ON COLUMN facts.daily_nutrition.avg_confidence IS 'Average confidence level of logged food entries';

-- =============================================================================
-- facts.daily_finance - Daily financial summary
-- =============================================================================
CREATE TABLE facts.daily_finance (
    date DATE PRIMARY KEY,

    -- Totals (from normalized.transactions)
    total_spent DECIMAL(10,2) DEFAULT 0,
    total_income DECIMAL(10,2) DEFAULT 0,
    net_flow DECIMAL(10,2) DEFAULT 0,       -- income - spent

    -- Category breakdowns (AED)
    grocery_spent DECIMAL(10,2) DEFAULT 0,
    food_delivery_spent DECIMAL(10,2) DEFAULT 0,
    restaurant_spent DECIMAL(10,2) DEFAULT 0,
    transport_spent DECIMAL(10,2) DEFAULT 0,
    utilities_spent DECIMAL(10,2) DEFAULT 0,
    shopping_spent DECIMAL(10,2) DEFAULT 0,
    subscriptions_spent DECIMAL(10,2) DEFAULT 0,
    other_spent DECIMAL(10,2) DEFAULT 0,

    -- Counts
    transaction_count INT DEFAULT 0,
    expense_count INT DEFAULT 0,
    income_count INT DEFAULT 0,

    -- Refresh tracking
    refreshed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_facts_finance_refreshed ON facts.daily_finance(refreshed_at DESC);

COMMENT ON TABLE facts.daily_finance IS 'Daily finance summary with category breakdowns.';
COMMENT ON COLUMN facts.daily_finance.net_flow IS 'Income minus spending for the day';

-- =============================================================================
-- facts.daily_summary - Unified daily view (replaces core.daily_summary)
-- =============================================================================
CREATE TABLE facts.daily_summary (
    date DATE PRIMARY KEY,

    -- Health highlights (from facts.daily_health)
    weight_kg DECIMAL(5,2),
    recovery_score INT,
    hrv DECIMAL(5,1),
    rhr INT,
    sleep_hours DECIMAL(4,2),
    day_strain DECIMAL(4,1),
    mood_score DECIMAL(3,1),
    energy_score DECIMAL(3,1),

    -- Nutrition highlights (from facts.daily_nutrition)
    calories INT,
    protein_g INT,
    carbs_g INT,
    fat_g INT,
    water_ml INT,

    -- Finance highlights (from facts.daily_finance)
    total_spent DECIMAL(10,2),
    grocery_spent DECIMAL(10,2),
    food_spent DECIMAL(10,2),               -- grocery + delivery + restaurant

    -- Meta
    data_completeness DECIMAL(3,2),
    notes TEXT,                             -- Day-level notes if any

    -- Refresh tracking
    refreshed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_facts_summary_refreshed ON facts.daily_summary(refreshed_at DESC);

COMMENT ON TABLE facts.daily_summary IS 'Unified daily view combining health, nutrition, and finance highlights.';
COMMENT ON COLUMN facts.daily_summary.food_spent IS 'Total food spending: grocery + delivery + restaurant';

-- =============================================================================
-- Refresh Functions
-- =============================================================================

-- -----------------------------------------------------------------------------
-- facts.refresh_daily_health(target_date DATE)
-- Recomputes health facts for a single date from normalized tables.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION facts.refresh_daily_health(target_date DATE)
RETURNS VOID AS $$
DECLARE
    v_completeness DECIMAL(3,2) := 0;
BEGIN
    INSERT INTO facts.daily_health (
        date,
        -- Recovery
        recovery_score, hrv, rhr, spo2, skin_temp_c,
        -- Sleep
        sleep_hours, sleep_quality, deep_sleep_hours, rem_sleep_hours,
        light_sleep_hours, time_in_bed_hours, sleep_efficiency,
        -- Strain
        day_strain, calories_burned, workout_count, average_hr, max_hr,
        -- Body
        weight_kg, body_fat_pct,
        -- Mood
        mood_score, energy_score, stress_score,
        -- Meta
        data_completeness, refreshed_at
    )
    SELECT
        target_date,
        -- Recovery
        r.recovery_score, r.hrv, r.rhr, r.spo2, r.skin_temp_c,
        -- Sleep (convert minutes to hours)
        CASE WHEN s.total_sleep_min IS NOT NULL
             THEN ROUND(s.total_sleep_min / 60.0, 2) END,
        s.sleep_performance,
        CASE WHEN s.deep_sleep_min IS NOT NULL
             THEN ROUND(s.deep_sleep_min / 60.0, 2) END,
        CASE WHEN s.rem_sleep_min IS NOT NULL
             THEN ROUND(s.rem_sleep_min / 60.0, 2) END,
        CASE WHEN s.light_sleep_min IS NOT NULL
             THEN ROUND(s.light_sleep_min / 60.0, 2) END,
        CASE WHEN s.time_in_bed_min IS NOT NULL
             THEN ROUND(s.time_in_bed_min / 60.0, 2) END,
        s.sleep_efficiency,
        -- Strain
        st.day_strain, st.calories_burned, st.workout_count, st.average_hr, st.max_hr,
        -- Body (latest weight and body_fat for the day)
        w.value,
        bf.value,
        -- Mood (average for the day)
        m.avg_mood, m.avg_energy, m.avg_stress,
        -- Compute completeness (each major category = 0.25)
        (
            (CASE WHEN r.recovery_score IS NOT NULL THEN 0.25 ELSE 0 END) +
            (CASE WHEN s.total_sleep_min IS NOT NULL THEN 0.25 ELSE 0 END) +
            (CASE WHEN st.day_strain IS NOT NULL THEN 0.25 ELSE 0 END) +
            (CASE WHEN w.value IS NOT NULL THEN 0.25 ELSE 0 END)
        )::DECIMAL(3,2),
        NOW()
    FROM
        (SELECT 1) dummy
        LEFT JOIN normalized.daily_recovery r ON r.date = target_date
        LEFT JOIN normalized.daily_sleep s ON s.date = target_date
        LEFT JOIN normalized.daily_strain st ON st.date = target_date
        LEFT JOIN LATERAL (
            SELECT value FROM normalized.body_metrics
            WHERE date = target_date AND metric_type = 'weight'
            ORDER BY recorded_at DESC LIMIT 1
        ) w ON TRUE
        LEFT JOIN LATERAL (
            SELECT value FROM normalized.body_metrics
            WHERE date = target_date AND metric_type = 'body_fat'
            ORDER BY recorded_at DESC LIMIT 1
        ) bf ON TRUE
        LEFT JOIN LATERAL (
            SELECT
                ROUND(AVG(mood_score), 1) as avg_mood,
                ROUND(AVG(energy_score), 1) as avg_energy,
                ROUND(AVG(stress_score), 1) as avg_stress
            FROM normalized.mood_log
            WHERE date = target_date
        ) m ON TRUE
    ON CONFLICT (date) DO UPDATE SET
        recovery_score = EXCLUDED.recovery_score,
        hrv = EXCLUDED.hrv,
        rhr = EXCLUDED.rhr,
        spo2 = EXCLUDED.spo2,
        skin_temp_c = EXCLUDED.skin_temp_c,
        sleep_hours = EXCLUDED.sleep_hours,
        sleep_quality = EXCLUDED.sleep_quality,
        deep_sleep_hours = EXCLUDED.deep_sleep_hours,
        rem_sleep_hours = EXCLUDED.rem_sleep_hours,
        light_sleep_hours = EXCLUDED.light_sleep_hours,
        time_in_bed_hours = EXCLUDED.time_in_bed_hours,
        sleep_efficiency = EXCLUDED.sleep_efficiency,
        day_strain = EXCLUDED.day_strain,
        calories_burned = EXCLUDED.calories_burned,
        workout_count = EXCLUDED.workout_count,
        average_hr = EXCLUDED.average_hr,
        max_hr = EXCLUDED.max_hr,
        weight_kg = EXCLUDED.weight_kg,
        body_fat_pct = EXCLUDED.body_fat_pct,
        mood_score = EXCLUDED.mood_score,
        energy_score = EXCLUDED.energy_score,
        stress_score = EXCLUDED.stress_score,
        data_completeness = EXCLUDED.data_completeness,
        refreshed_at = NOW();
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION facts.refresh_daily_health(DATE) IS 'Recomputes facts.daily_health for a single date from normalized tables';

-- -----------------------------------------------------------------------------
-- facts.refresh_daily_nutrition(target_date DATE)
-- Recomputes nutrition facts for a single date.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION facts.refresh_daily_nutrition(target_date DATE)
RETURNS VOID AS $$
BEGIN
    INSERT INTO facts.daily_nutrition (
        date,
        calories, protein_g, carbs_g, fat_g, fiber_g,
        meals_logged, entries_logged,
        water_ml,
        avg_confidence, has_all_meals,
        refreshed_at
    )
    SELECT
        target_date,
        -- Food totals
        f.total_calories,
        f.total_protein,
        f.total_carbs,
        f.total_fat,
        f.total_fiber,
        f.meal_count,
        f.entry_count,
        -- Water
        COALESCE(wl.total_water, 0),
        -- Confidence (mode/most common)
        f.mode_confidence,
        -- Has all meals
        f.has_breakfast AND f.has_lunch AND f.has_dinner,
        NOW()
    FROM
        (SELECT 1) dummy
        LEFT JOIN LATERAL (
            SELECT
                COALESCE(SUM(calories), 0)::INT as total_calories,
                COALESCE(SUM(protein_g), 0)::INT as total_protein,
                COALESCE(SUM(carbs_g), 0)::INT as total_carbs,
                COALESCE(SUM(fat_g), 0)::INT as total_fat,
                COALESCE(SUM(fiber_g), 0)::INT as total_fiber,
                COUNT(DISTINCT meal_time) as meal_count,
                COUNT(*) as entry_count,
                BOOL_OR(meal_time = 'breakfast') as has_breakfast,
                BOOL_OR(meal_time = 'lunch') as has_lunch,
                BOOL_OR(meal_time = 'dinner') as has_dinner,
                MODE() WITHIN GROUP (ORDER BY confidence) as mode_confidence
            FROM normalized.food_log
            WHERE date = target_date
        ) f ON TRUE
        LEFT JOIN LATERAL (
            SELECT COALESCE(SUM(amount_ml), 0) as total_water
            FROM normalized.water_log
            WHERE date = target_date
        ) wl ON TRUE
    ON CONFLICT (date) DO UPDATE SET
        calories = EXCLUDED.calories,
        protein_g = EXCLUDED.protein_g,
        carbs_g = EXCLUDED.carbs_g,
        fat_g = EXCLUDED.fat_g,
        fiber_g = EXCLUDED.fiber_g,
        meals_logged = EXCLUDED.meals_logged,
        entries_logged = EXCLUDED.entries_logged,
        water_ml = EXCLUDED.water_ml,
        avg_confidence = EXCLUDED.avg_confidence,
        has_all_meals = EXCLUDED.has_all_meals,
        refreshed_at = NOW();
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION facts.refresh_daily_nutrition(DATE) IS 'Recomputes facts.daily_nutrition for a single date from normalized tables';

-- -----------------------------------------------------------------------------
-- facts.refresh_daily_finance(target_date DATE)
-- Recomputes finance facts for a single date.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION facts.refresh_daily_finance(target_date DATE)
RETURNS VOID AS $$
BEGIN
    INSERT INTO facts.daily_finance (
        date,
        total_spent, total_income, net_flow,
        grocery_spent, food_delivery_spent, restaurant_spent,
        transport_spent, utilities_spent, shopping_spent,
        subscriptions_spent, other_spent,
        transaction_count, expense_count, income_count,
        refreshed_at
    )
    SELECT
        target_date,
        -- Totals
        COALESCE(SUM(CASE WHEN NOT is_income AND NOT is_internal_transfer THEN amount END), 0),
        COALESCE(SUM(CASE WHEN is_income THEN amount END), 0),
        COALESCE(SUM(CASE WHEN is_income THEN amount ELSE -amount END), 0),
        -- Category breakdowns (expenses only)
        COALESCE(SUM(CASE WHEN category = 'grocery' THEN amount END), 0),
        COALESCE(SUM(CASE WHEN category = 'food_delivery' THEN amount END), 0),
        COALESCE(SUM(CASE WHEN category = 'restaurant' THEN amount END), 0),
        COALESCE(SUM(CASE WHEN category = 'transport' THEN amount END), 0),
        COALESCE(SUM(CASE WHEN category = 'utilities' THEN amount END), 0),
        COALESCE(SUM(CASE WHEN category = 'shopping' THEN amount END), 0),
        COALESCE(SUM(CASE WHEN category = 'subscriptions' THEN amount END), 0),
        COALESCE(SUM(CASE WHEN category NOT IN ('grocery', 'food_delivery', 'restaurant', 'transport', 'utilities', 'shopping', 'subscriptions')
                           AND NOT is_income AND NOT is_internal_transfer THEN amount END), 0),
        -- Counts
        COUNT(*)::INT,
        COUNT(CASE WHEN NOT is_income AND NOT is_internal_transfer THEN 1 END)::INT,
        COUNT(CASE WHEN is_income THEN 1 END)::INT,
        NOW()
    FROM normalized.transactions
    WHERE date = target_date
    GROUP BY target_date
    ON CONFLICT (date) DO UPDATE SET
        total_spent = EXCLUDED.total_spent,
        total_income = EXCLUDED.total_income,
        net_flow = EXCLUDED.net_flow,
        grocery_spent = EXCLUDED.grocery_spent,
        food_delivery_spent = EXCLUDED.food_delivery_spent,
        restaurant_spent = EXCLUDED.restaurant_spent,
        transport_spent = EXCLUDED.transport_spent,
        utilities_spent = EXCLUDED.utilities_spent,
        shopping_spent = EXCLUDED.shopping_spent,
        subscriptions_spent = EXCLUDED.subscriptions_spent,
        other_spent = EXCLUDED.other_spent,
        transaction_count = EXCLUDED.transaction_count,
        expense_count = EXCLUDED.expense_count,
        income_count = EXCLUDED.income_count,
        refreshed_at = NOW();

    -- Handle days with no transactions
    INSERT INTO facts.daily_finance (date, refreshed_at)
    VALUES (target_date, NOW())
    ON CONFLICT (date) DO NOTHING;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION facts.refresh_daily_finance(DATE) IS 'Recomputes facts.daily_finance for a single date from normalized.transactions';

-- -----------------------------------------------------------------------------
-- facts.refresh_daily_summary(target_date DATE)
-- Recomputes the unified daily summary from other facts tables.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION facts.refresh_daily_summary(target_date DATE)
RETURNS VOID AS $$
BEGIN
    -- Ensure component facts are up to date
    PERFORM facts.refresh_daily_health(target_date);
    PERFORM facts.refresh_daily_nutrition(target_date);
    PERFORM facts.refresh_daily_finance(target_date);

    -- Build summary
    INSERT INTO facts.daily_summary (
        date,
        -- Health
        weight_kg, recovery_score, hrv, rhr, sleep_hours, day_strain,
        mood_score, energy_score,
        -- Nutrition
        calories, protein_g, carbs_g, fat_g, water_ml,
        -- Finance
        total_spent, grocery_spent, food_spent,
        -- Meta
        data_completeness,
        refreshed_at
    )
    SELECT
        target_date,
        -- Health
        h.weight_kg, h.recovery_score, h.hrv, h.rhr, h.sleep_hours, h.day_strain,
        h.mood_score, h.energy_score,
        -- Nutrition
        n.calories, n.protein_g, n.carbs_g, n.fat_g, n.water_ml,
        -- Finance
        f.total_spent, f.grocery_spent,
        COALESCE(f.grocery_spent, 0) + COALESCE(f.food_delivery_spent, 0) + COALESCE(f.restaurant_spent, 0),
        -- Meta
        h.data_completeness,
        NOW()
    FROM
        (SELECT 1) dummy
        LEFT JOIN facts.daily_health h ON h.date = target_date
        LEFT JOIN facts.daily_nutrition n ON n.date = target_date
        LEFT JOIN facts.daily_finance f ON f.date = target_date
    ON CONFLICT (date) DO UPDATE SET
        weight_kg = EXCLUDED.weight_kg,
        recovery_score = EXCLUDED.recovery_score,
        hrv = EXCLUDED.hrv,
        rhr = EXCLUDED.rhr,
        sleep_hours = EXCLUDED.sleep_hours,
        day_strain = EXCLUDED.day_strain,
        mood_score = EXCLUDED.mood_score,
        energy_score = EXCLUDED.energy_score,
        calories = EXCLUDED.calories,
        protein_g = EXCLUDED.protein_g,
        carbs_g = EXCLUDED.carbs_g,
        fat_g = EXCLUDED.fat_g,
        water_ml = EXCLUDED.water_ml,
        total_spent = EXCLUDED.total_spent,
        grocery_spent = EXCLUDED.grocery_spent,
        food_spent = EXCLUDED.food_spent,
        data_completeness = EXCLUDED.data_completeness,
        refreshed_at = NOW();
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION facts.refresh_daily_summary(DATE) IS 'Recomputes facts.daily_summary by refreshing all component facts first';

-- -----------------------------------------------------------------------------
-- facts.refresh_date_range(start_date DATE, end_date DATE)
-- Recomputes all facts for a date range. Useful for backfills.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION facts.refresh_date_range(start_date DATE, end_date DATE)
RETURNS INT AS $$
DECLARE
    iter_date DATE;
    processed INT := 0;
BEGIN
    iter_date := start_date;
    WHILE iter_date <= end_date LOOP
        PERFORM facts.refresh_daily_summary(iter_date);
        processed := processed + 1;
        iter_date := iter_date + 1;
    END LOOP;
    RETURN processed;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION facts.refresh_date_range(DATE, DATE) IS 'Recomputes all facts for a date range. Returns number of days processed.';

-- -----------------------------------------------------------------------------
-- facts.rebuild_all()
-- Rebuilds all facts from scratch. Use carefully!
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION facts.rebuild_all()
RETURNS INT AS $$
DECLARE
    min_dt DATE;
    max_dt DATE;
    processed INT;
BEGIN
    -- Find date range from normalized tables
    SELECT MIN(d) INTO min_dt FROM (
        SELECT MIN(date) as d FROM normalized.daily_recovery
        UNION ALL SELECT MIN(date) FROM normalized.daily_sleep
        UNION ALL SELECT MIN(date) FROM normalized.daily_strain
        UNION ALL SELECT MIN(date) FROM normalized.body_metrics
        UNION ALL SELECT MIN(date) FROM normalized.transactions
        UNION ALL SELECT MIN(date) FROM normalized.food_log
    ) dates;

    SELECT MAX(d) INTO max_dt FROM (
        SELECT MAX(date) as d FROM normalized.daily_recovery
        UNION ALL SELECT MAX(date) FROM normalized.daily_sleep
        UNION ALL SELECT MAX(date) FROM normalized.daily_strain
        UNION ALL SELECT MAX(date) FROM normalized.body_metrics
        UNION ALL SELECT MAX(date) FROM normalized.transactions
        UNION ALL SELECT MAX(date) FROM normalized.food_log
    ) dates;

    IF min_dt IS NULL OR max_dt IS NULL THEN
        RETURN 0;
    END IF;

    -- Truncate existing facts (faster than delete)
    TRUNCATE facts.daily_health, facts.daily_nutrition, facts.daily_finance, facts.daily_summary;

    -- Rebuild
    processed := facts.refresh_date_range(min_dt, max_dt);

    RETURN processed;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION facts.rebuild_all() IS 'Truncates and rebuilds all facts from normalized tables. Use carefully!';

COMMIT;
