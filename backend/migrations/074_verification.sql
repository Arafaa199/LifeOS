-- Migration 074: Meal Coverage Gaps Verification

-- Test 1: View exists and returns data for last 30 days
SELECT COUNT(*) as total_days
FROM life.v_meal_coverage_gaps;

-- Test 2: Show gap distribution
SELECT
    gap_status,
    COUNT(*) as day_count
FROM life.v_meal_coverage_gaps
GROUP BY gap_status
ORDER BY day_count DESC;

-- Test 3: Identify HealthKit → no meals gaps
SELECT
    day,
    has_healthkit,
    has_inferred_meals,
    gap_status
FROM life.v_meal_coverage_gaps
WHERE gap_healthkit_no_meals IS NOT NULL
ORDER BY day DESC
LIMIT 5;

-- Test 4: Identify meals → no food TX gaps
SELECT
    day,
    has_inferred_meals,
    has_food_transactions,
    gap_status
FROM life.v_meal_coverage_gaps
WHERE gap_meals_no_food_tx IS NOT NULL
ORDER BY day DESC
LIMIT 5;

-- Test 5: Summary statistics
SELECT
    COUNT(*) FILTER (WHERE has_healthkit) as days_with_healthkit,
    COUNT(*) FILTER (WHERE has_inferred_meals) as days_with_inferred_meals,
    COUNT(*) FILTER (WHERE has_food_transactions) as days_with_food_tx,
    COUNT(*) FILTER (WHERE has_confirmed_meals) as days_with_confirmed_meals,
    COUNT(*) FILTER (WHERE gap_healthkit_no_meals IS NOT NULL) as healthkit_no_meals_gaps,
    COUNT(*) FILTER (WHERE gap_meals_no_food_tx IS NOT NULL) as meals_no_food_tx_gaps,
    COUNT(*) FILTER (WHERE gap_confirmed_no_signals IS NOT NULL) as confirmed_no_signals_gaps
FROM life.v_meal_coverage_gaps;

-- Test 6: Recent gaps (last 7 days)
SELECT
    day,
    has_healthkit,
    has_inferred_meals,
    has_food_transactions,
    has_confirmed_meals,
    gap_status
FROM life.v_meal_coverage_gaps
WHERE day >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY day DESC;
