-- Migration 074: Meal Coverage Gaps View
-- Created: 2026-01-26
-- Purpose: Identify meal-related data quality issues and coverage gaps

-- Create view showing meal coverage gaps
CREATE OR REPLACE VIEW life.v_meal_coverage_gaps AS
WITH daily_signals AS (
    SELECT
        d.day,
        -- HealthKit data availability
        EXISTS (
            SELECT 1 FROM raw.healthkit_samples h
            WHERE h.start_date::date = d.day
        ) as has_healthkit,
        -- Inferred meals availability
        EXISTS (
            SELECT 1 FROM life.v_inferred_meals m
            WHERE m.inferred_at_date = d.day
        ) as has_inferred_meals,
        -- Restaurant/grocery transactions
        EXISTS (
            SELECT 1 FROM finance.transactions t
            WHERE finance.to_business_date(t.transaction_at) = d.day
            AND t.category IN ('Restaurant', 'Grocery')
        ) as has_food_transactions,
        -- Confirmed meals
        EXISTS (
            SELECT 1 FROM life.meal_confirmations mc
            WHERE mc.inferred_meal_date = d.day
        ) as has_confirmed_meals,
        -- Behavioral signals (location, TV)
        EXISTS (
            SELECT 1 FROM life.daily_behavioral_summary b
            WHERE b.day = d.day
        ) as has_behavioral_signals
    FROM generate_series(
        CURRENT_DATE - INTERVAL '30 days',
        CURRENT_DATE,
        '1 day'::interval
    ) AS d(day)
)
SELECT
    day,
    has_healthkit,
    has_inferred_meals,
    has_food_transactions,
    has_confirmed_meals,
    has_behavioral_signals,
    -- Gap detection: HealthKit but no inferred meals
    CASE
        WHEN has_healthkit AND NOT has_inferred_meals THEN 'healthkit_no_meals'
        ELSE NULL
    END as gap_healthkit_no_meals,
    -- Gap detection: Inferred meals but no restaurant/grocery TX
    CASE
        WHEN has_inferred_meals AND NOT has_food_transactions THEN 'meals_no_food_tx'
        ELSE NULL
    END as gap_meals_no_food_tx,
    -- Gap detection: Confirmed meals but missing signals
    CASE
        WHEN has_confirmed_meals AND NOT has_behavioral_signals THEN 'confirmed_no_signals'
        ELSE NULL
    END as gap_confirmed_no_signals,
    -- Overall gap status
    CASE
        WHEN has_healthkit AND NOT has_inferred_meals THEN 'inference_failure'
        WHEN has_inferred_meals AND NOT has_food_transactions THEN 'missing_context'
        WHEN has_confirmed_meals AND NOT has_behavioral_signals THEN 'signal_loss'
        WHEN has_healthkit OR has_inferred_meals OR has_food_transactions THEN 'partial_data'
        ELSE 'no_meal_data'
    END as gap_status
FROM daily_signals
ORDER BY day DESC;

COMMENT ON VIEW life.v_meal_coverage_gaps IS 'Identifies meal-related data quality issues: HealthKit without meals, meals without transactions, confirmed meals without signals';
