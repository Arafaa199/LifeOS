-- Migration: 006_enhance_life_schema
-- Adds missing columns to life.daily_facts and creates life.feed_status view
-- For Dashboard Milestone 1

-- ============================================================================
-- Add missing columns to life.daily_facts
-- ============================================================================

-- Add spending_by_category JSONB column
ALTER TABLE life.daily_facts
ADD COLUMN IF NOT EXISTS spending_by_category JSONB DEFAULT '{}'::jsonb;

-- Add weight delta columns
ALTER TABLE life.daily_facts
ADD COLUMN IF NOT EXISTS weight_delta_7d NUMERIC(4,2);

ALTER TABLE life.daily_facts
ADD COLUMN IF NOT EXISTS weight_delta_30d NUMERIC(4,2);

-- Add sleep_hours column (derived from sleep_minutes for convenience)
ALTER TABLE life.daily_facts
ADD COLUMN IF NOT EXISTS sleep_hours NUMERIC(4,2);

-- Add deep_sleep_hours column (derived from deep_sleep_minutes)
ALTER TABLE life.daily_facts
ADD COLUMN IF NOT EXISTS deep_sleep_hours NUMERIC(4,2);

-- ============================================================================
-- life.feed_status - View for data source health
-- ============================================================================

CREATE OR REPLACE VIEW life.feed_status AS
WITH sources AS (
    -- WHOOP via Home Assistant
    SELECT
        'whoop' AS source,
        MAX(created_at) AS last_event_at,
        COUNT(*) FILTER (WHERE date = CURRENT_DATE) AS events_today
    FROM health.whoop_recovery

    UNION ALL

    -- HealthKit (weight from health.metrics)
    SELECT
        'healthkit' AS source,
        MAX(created_at) AS last_event_at,
        COUNT(*) FILTER (WHERE date = CURRENT_DATE) AS events_today
    FROM health.metrics
    WHERE source = 'healthkit'

    UNION ALL

    -- Bank SMS (finance.transactions)
    SELECT
        'bank_sms' AS source,
        MAX(created_at) AS last_event_at,
        COUNT(*) FILTER (WHERE date = CURRENT_DATE) AS events_today
    FROM finance.transactions

    UNION ALL

    -- Manual entries (nutrition.food_log)
    SELECT
        'manual' AS source,
        MAX(created_at) AS last_event_at,
        COUNT(*) FILTER (WHERE date = CURRENT_DATE) AS events_today
    FROM nutrition.food_log
)
SELECT
    source,
    last_event_at,
    events_today,
    CASE
        WHEN last_event_at IS NULL THEN 'error'
        WHEN last_event_at >= NOW() - INTERVAL '1 hour' THEN 'ok'
        WHEN last_event_at >= NOW() - INTERVAL '24 hours' THEN 'stale'
        ELSE 'error'
    END AS status
FROM sources;

-- ============================================================================
-- Update life.refresh_daily_facts to populate new columns
-- ============================================================================

CREATE OR REPLACE FUNCTION life.refresh_daily_facts(target_day date DEFAULT NULL::date)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    the_day DATE := COALESCE(target_day, (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Dubai')::date);
    weight_7d_ago NUMERIC(5,2);
    weight_30d_ago NUMERIC(5,2);
    current_weight NUMERIC(5,2);
BEGIN
    -- Get weight values for delta calculations
    SELECT value INTO current_weight
    FROM health.metrics
    WHERE metric_type = 'weight' AND recorded_at::date = the_day
    ORDER BY recorded_at DESC LIMIT 1;

    SELECT value INTO weight_7d_ago
    FROM health.metrics
    WHERE metric_type = 'weight'
      AND recorded_at::date BETWEEN the_day - INTERVAL '7 days' AND the_day - INTERVAL '1 day'
    ORDER BY recorded_at DESC LIMIT 1;

    SELECT value INTO weight_30d_ago
    FROM health.metrics
    WHERE metric_type = 'weight'
      AND recorded_at::date BETWEEN the_day - INTERVAL '30 days' AND the_day - INTERVAL '1 day'
    ORDER BY recorded_at DESC LIMIT 1;

    INSERT INTO life.daily_facts (
        day,
        -- Health: Recovery
        recovery_score, hrv, rhr, spo2,
        -- Health: Sleep (original minutes)
        sleep_minutes, deep_sleep_minutes, rem_sleep_minutes, sleep_efficiency, sleep_performance,
        -- Health: Sleep (new hours columns)
        sleep_hours, deep_sleep_hours,
        -- Health: Strain
        strain, calories_active,
        -- Health: Body
        weight_kg, weight_delta_7d, weight_delta_30d,
        -- Finance
        spend_total, spend_groceries, spend_restaurants, spend_transport, income_total, transaction_count,
        spending_by_category,
        -- Nutrition
        meals_logged, water_ml, calories_consumed, protein_g,
        -- Meta
        data_completeness, computed_at
    )
    SELECT
        the_day,
        -- Recovery (from health.whoop_recovery)
        r.recovery_score,
        r.hrv_rmssd,
        r.rhr,
        r.spo2,
        -- Sleep (original minutes)
        s.time_in_bed_min - COALESCE(s.awake_min, 0),
        s.deep_sleep_min,
        s.rem_sleep_min,
        s.sleep_efficiency,
        s.sleep_performance,
        -- Sleep (hours for dashboard)
        ROUND((s.time_in_bed_min - COALESCE(s.awake_min, 0))::numeric / 60.0, 2),
        ROUND(s.deep_sleep_min::numeric / 60.0, 2),
        -- Strain (from health.whoop_strain)
        st.day_strain,
        st.calories_active,
        -- Weight with deltas
        current_weight,
        CASE WHEN current_weight IS NOT NULL AND weight_7d_ago IS NOT NULL
             THEN current_weight - weight_7d_ago ELSE NULL END,
        CASE WHEN current_weight IS NOT NULL AND weight_30d_ago IS NOT NULL
             THEN current_weight - weight_30d_ago ELSE NULL END,
        -- Finance (from finance.transactions)
        COALESCE(ABS(SUM(CASE WHEN t.amount < 0 THEN t.amount ELSE 0 END)), 0),
        COALESCE(ABS(SUM(CASE WHEN t.amount < 0 AND t.category = 'Groceries' THEN t.amount ELSE 0 END)), 0),
        COALESCE(ABS(SUM(CASE WHEN t.amount < 0 AND t.category IN ('Dining', 'Restaurants', 'Food Delivery') THEN t.amount ELSE 0 END)), 0),
        COALESCE(ABS(SUM(CASE WHEN t.amount < 0 AND t.category = 'Transport' THEN t.amount ELSE 0 END)), 0),
        COALESCE(SUM(CASE WHEN t.amount > 0 THEN t.amount ELSE 0 END), 0),
        COUNT(t.id),
        -- Spending by category JSONB
        COALESCE(
            (SELECT jsonb_object_agg(COALESCE(category, 'other'), cat_total)
             FROM (
                 SELECT category, ABS(SUM(amount)) AS cat_total
                 FROM finance.transactions
                 WHERE date = the_day AND amount < 0
                 GROUP BY category
             ) cats),
            '{}'::jsonb
        ),
        -- Nutrition (from core.daily_summary)
        COALESCE(ds.meals_logged, 0),
        COALESCE(ds.water_ml, 0),
        ds.calories_consumed,
        ds.protein_g,
        -- Data completeness score
        (
            CASE WHEN r.recovery_score IS NOT NULL THEN 0.2 ELSE 0 END +
            CASE WHEN s.time_in_bed_min IS NOT NULL THEN 0.2 ELSE 0 END +
            CASE WHEN st.day_strain IS NOT NULL THEN 0.15 ELSE 0 END +
            CASE WHEN current_weight IS NOT NULL THEN 0.15 ELSE 0 END +
            CASE WHEN COUNT(t.id) > 0 THEN 0.15 ELSE 0 END +
            CASE WHEN ds.calories_consumed IS NOT NULL THEN 0.15 ELSE 0 END
        ),
        NOW()
    FROM
        (SELECT 1) AS dummy
        LEFT JOIN health.whoop_recovery r ON r.date = the_day
        LEFT JOIN health.whoop_sleep s ON s.date = the_day
        LEFT JOIN health.whoop_strain st ON st.date = the_day
        LEFT JOIN finance.transactions t ON t.date = the_day
        LEFT JOIN core.daily_summary ds ON ds.date = the_day
    GROUP BY
        r.recovery_score, r.hrv_rmssd, r.rhr, r.spo2,
        s.time_in_bed_min, s.awake_min, s.deep_sleep_min, s.rem_sleep_min, s.sleep_efficiency, s.sleep_performance,
        st.day_strain, st.calories_active,
        ds.meals_logged, ds.water_ml, ds.calories_consumed, ds.protein_g
    ON CONFLICT (day) DO UPDATE SET
        recovery_score = EXCLUDED.recovery_score,
        hrv = EXCLUDED.hrv,
        rhr = EXCLUDED.rhr,
        spo2 = EXCLUDED.spo2,
        sleep_minutes = EXCLUDED.sleep_minutes,
        deep_sleep_minutes = EXCLUDED.deep_sleep_minutes,
        rem_sleep_minutes = EXCLUDED.rem_sleep_minutes,
        sleep_efficiency = EXCLUDED.sleep_efficiency,
        sleep_performance = EXCLUDED.sleep_performance,
        sleep_hours = EXCLUDED.sleep_hours,
        deep_sleep_hours = EXCLUDED.deep_sleep_hours,
        strain = EXCLUDED.strain,
        calories_active = EXCLUDED.calories_active,
        weight_kg = EXCLUDED.weight_kg,
        weight_delta_7d = EXCLUDED.weight_delta_7d,
        weight_delta_30d = EXCLUDED.weight_delta_30d,
        spend_total = EXCLUDED.spend_total,
        spend_groceries = EXCLUDED.spend_groceries,
        spend_restaurants = EXCLUDED.spend_restaurants,
        spend_transport = EXCLUDED.spend_transport,
        income_total = EXCLUDED.income_total,
        transaction_count = EXCLUDED.transaction_count,
        spending_by_category = EXCLUDED.spending_by_category,
        meals_logged = EXCLUDED.meals_logged,
        water_ml = EXCLUDED.water_ml,
        calories_consumed = EXCLUDED.calories_consumed,
        protein_g = EXCLUDED.protein_g,
        data_completeness = EXCLUDED.data_completeness,
        computed_at = NOW();
END;
$function$;

-- Grant permissions
GRANT SELECT ON life.feed_status TO nexus;

-- Add comments
COMMENT ON VIEW life.feed_status IS 'Data source health status for dashboard. Shows last sync time and status (ok/stale/error) per source.';
COMMENT ON COLUMN life.daily_facts.spending_by_category IS 'JSONB object with category names as keys and totals as values';
COMMENT ON COLUMN life.daily_facts.weight_delta_7d IS 'Weight change from 7 days ago (kg)';
COMMENT ON COLUMN life.daily_facts.weight_delta_30d IS 'Weight change from 30 days ago (kg)';
COMMENT ON COLUMN life.daily_facts.sleep_hours IS 'Total sleep in hours (derived from sleep_minutes)';
COMMENT ON COLUMN life.daily_facts.deep_sleep_hours IS 'Deep sleep in hours (derived from deep_sleep_minutes)';
