-- Migration 075: Coverage Truth Report
-- Creates single view showing complete coverage truth for last 30 days

CREATE OR REPLACE VIEW life.v_coverage_truth AS
WITH daily_stats AS (
    SELECT
        day,
        -- Finance data
        (SELECT COUNT(*) FROM finance.transactions WHERE DATE(transaction_at AT TIME ZONE 'Asia/Dubai') = day) as transactions_found,
        -- Meal data
        (SELECT COUNT(*) FROM life.v_inferred_meals WHERE inferred_at_date = day) as inferred_meals,
        (SELECT COUNT(*) FROM life.meal_confirmations WHERE inferred_meal_date = day AND user_action = 'confirmed') as confirmed_meals,
        -- Calculate total meals (inferred + confirmed, deduplicated)
        (SELECT COUNT(DISTINCT COALESCE(im.inferred_at_time::TEXT, mc.inferred_meal_time::TEXT))
         FROM life.v_inferred_meals im
         FULL OUTER JOIN life.meal_confirmations mc
             ON im.inferred_at_date = mc.inferred_meal_date
             AND im.inferred_at_time = mc.inferred_meal_time
         WHERE COALESCE(im.inferred_at_date, mc.inferred_meal_date) = day
        ) as meals_found
    FROM generate_series(
        CURRENT_DATE - INTERVAL '30 days',
        CURRENT_DATE,
        '1 day'::INTERVAL
    ) AS day
)
SELECT
    day::DATE,
    transactions_found::INTEGER,
    meals_found::INTEGER,
    inferred_meals::INTEGER,
    confirmed_meals::INTEGER,
    CASE
        -- Complete coverage: both finance and meals present
        WHEN transactions_found > 0 AND meals_found > 0 THEN 'complete'
        -- Gap: have data but missing the other type
        WHEN transactions_found > 0 AND meals_found = 0 THEN 'gap'
        WHEN transactions_found = 0 AND meals_found > 0 THEN 'gap'
        -- Expected gap: no data for this day (normal - not every day has activity)
        ELSE 'expected_gap'
    END as gap_status,
    CASE
        -- Explain actual gaps (days where we have one type of data but not the other)
        WHEN transactions_found > 0 AND meals_found = 0
            THEN 'Have transactions but no meals - HealthKit/behavioral signals may be incomplete for this day'
        WHEN transactions_found = 0 AND meals_found > 0
            THEN 'Have meals but no transactions - possible cash-only day or no spending'
        WHEN inferred_meals > 0 AND confirmed_meals = 0
            THEN 'Meals inferred but not yet confirmed via iOS app'
        WHEN transactions_found = 0 AND meals_found = 0 AND EXTRACT(DOW FROM day) IN (5, 6)
            THEN 'Weekend - no data expected'
        WHEN transactions_found = 0 AND meals_found = 0
            THEN 'No activity recorded - expected for inactive days'
        ELSE NULL -- No explanation needed for complete days
    END as explanation
FROM daily_stats
ORDER BY day DESC;

COMMENT ON VIEW life.v_coverage_truth IS 'Complete coverage truth for last 30 days - shows transactions, meals, and gap status with explanations. Only flags as "gap" when one data type exists but the other is missing.';
