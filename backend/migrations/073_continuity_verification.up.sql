-- Migration 073: Continuity Verification View
-- Task: TASK-CONTINUITY.2
-- Purpose: Verify data pipeline continuity for last 7 days

CREATE OR REPLACE VIEW life.v_continuity_check AS
WITH date_range AS (
    SELECT generate_series(
        CURRENT_DATE - INTERVAL '7 days',
        CURRENT_DATE,
        INTERVAL '1 day'
    )::DATE as day
),
healthkit_days AS (
    SELECT DISTINCT DATE(start_date AT TIME ZONE 'Asia/Dubai') as day
    FROM raw.healthkit_samples
    WHERE start_date >= CURRENT_DATE - INTERVAL '7 days'
),
inferred_meal_days AS (
    SELECT DISTINCT inferred_at_date as day
    FROM life.v_inferred_meals
    WHERE inferred_at_date >= CURRENT_DATE - INTERVAL '7 days'
),
confirmed_meal_days AS (
    SELECT DISTINCT inferred_meal_date as day
    FROM life.meal_confirmations
    WHERE inferred_meal_date >= CURRENT_DATE - INTERVAL '7 days'
      AND user_action = 'confirmed'
),
orphan_pending_meals AS (
    SELECT
        inferred_at_date as day,
        COUNT(*) as orphan_count
    FROM life.v_inferred_meals
    WHERE inferred_at_date < CURRENT_DATE - INTERVAL '1 day'  -- Older than 24h
      AND confirmation_status = 'pending'  -- Use confirmation_status from view
    GROUP BY inferred_at_date
)
SELECT
    dr.day,
    COALESCE(hk.day IS NOT NULL, false) as has_healthkit_data,
    COALESCE(im.day IS NOT NULL, false) as has_inferred_meals,
    COALESCE(cm.day IS NOT NULL, false) as has_confirmed_meals,
    COALESCE(opm.orphan_count, 0) as orphan_pending_meals,
    -- Overall status
    CASE
        WHEN COALESCE(hk.day IS NOT NULL, false)
         AND COALESCE(im.day IS NOT NULL, false)
         AND COALESCE(opm.orphan_count, 0) = 0
        THEN 'ok'
        WHEN COALESCE(opm.orphan_count, 0) > 0
        THEN 'orphans_detected'
        WHEN dr.day < CURRENT_DATE
         AND NOT COALESCE(hk.day IS NOT NULL, false)
        THEN 'missing_healthkit'
        WHEN dr.day < CURRENT_DATE
         AND COALESCE(hk.day IS NOT NULL, false)
         AND NOT COALESCE(im.day IS NOT NULL, false)
        THEN 'missing_inferred_meals'
        ELSE 'pending'
    END as status
FROM date_range dr
LEFT JOIN healthkit_days hk ON dr.day = hk.day
LEFT JOIN inferred_meal_days im ON dr.day = im.day
LEFT JOIN confirmed_meal_days cm ON dr.day = cm.day
LEFT JOIN orphan_pending_meals opm ON dr.day = opm.day
ORDER BY dr.day DESC;

COMMENT ON VIEW life.v_continuity_check IS 'Continuity verification for last 7 days: HealthKit, inferred meals, confirmed meals, orphan detection';
