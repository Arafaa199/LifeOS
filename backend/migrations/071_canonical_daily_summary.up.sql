-- Migration 071: Canonical Daily Summary Materialized View
-- Purpose: Create single source of truth for daily summary data
-- Replaces: Multiple summary functions/views
-- Owner: TASK-VERIFY.3

-- Create materialized view combining all daily metrics
CREATE MATERIALIZED VIEW IF NOT EXISTS life.mv_daily_summary AS
SELECT
    day,

    -- Health metrics (from WHOOP + body metrics)
    recovery_score,
    hrv,
    rhr as resting_heart_rate,
    spo2,
    sleep_minutes,
    (sleep_minutes / 60.0)::NUMERIC(4,2) as sleep_hours,
    deep_sleep_minutes,
    (deep_sleep_minutes / 60.0)::NUMERIC(4,2) as deep_sleep_hours,
    rem_sleep_minutes,
    sleep_efficiency,
    sleep_performance,
    strain,
    calories_active,
    weight_kg,
    weight_delta_7d,
    weight_delta_30d,
    steps,

    -- Finance metrics
    spend_total,
    spend_groceries,
    spend_restaurants,
    spend_transport,
    income_total,
    transaction_count,
    spending_by_category,

    -- Nutrition metrics
    meals_logged,
    water_ml,
    calories_consumed,
    protein_g,

    -- Behavioral metrics
    first_motion_time,
    last_motion_time,

    -- TV hours (from behavioral events)
    (
        SELECT COALESCE(SUM(duration_minutes / 60.0), 0)::NUMERIC(4,2)
        FROM life.behavioral_events
        WHERE event_type = 'tv_session_end'
          AND (recorded_at AT TIME ZONE 'Asia/Dubai')::DATE = life.daily_facts.day
    ) as tv_hours,

    -- Time at home in minutes (from daily location summary view if exists, else 0)
    (
        SELECT COALESCE((hours_at_home * 60), 0)::INTEGER
        FROM life.daily_location_summary
        WHERE day = life.daily_facts.day
    ) as time_at_home_minutes,

    -- Sleep detection time (from behavioral events metadata)
    (
        SELECT (recorded_at AT TIME ZONE 'Asia/Dubai')::TIME
        FROM life.behavioral_events
        WHERE event_type = 'sleep_detected'
          AND (recorded_at AT TIME ZONE 'Asia/Dubai')::DATE = life.daily_facts.day
        ORDER BY recorded_at DESC
        LIMIT 1
    ) as sleep_detected_at,

    -- Data quality metrics
    data_completeness,
    computed_at

FROM life.daily_facts
ORDER BY day DESC;

-- Create unique index on day
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_daily_summary_day ON life.mv_daily_summary (day);

-- Create function to refresh single day
CREATE OR REPLACE FUNCTION life.refresh_daily_summary(target_date DATE)
RETURNS VOID AS $$
BEGIN
    -- First refresh the underlying daily_facts table
    PERFORM life.refresh_daily_facts(target_date);

    -- Then refresh the materialized view for that day
    -- PostgreSQL doesn't support partial refresh, so we refresh the whole view
    -- This is acceptable since it's fast (< 1s for 90 days)
    REFRESH MATERIALIZED VIEW CONCURRENTLY life.mv_daily_summary;
END;
$$ LANGUAGE plpgsql;

-- Create function to get daily summary as JSONB (for API compatibility)
CREATE OR REPLACE FUNCTION life.get_daily_summary_canonical(target_date DATE)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'date', day,
        'health', jsonb_build_object(
            'recovery_score', recovery_score,
            'hrv', hrv,
            'resting_heart_rate', resting_heart_rate,
            'spo2', spo2,
            'sleep_hours', sleep_hours,
            'deep_sleep_hours', deep_sleep_hours,
            'rem_sleep_minutes', rem_sleep_minutes,
            'sleep_efficiency', sleep_efficiency,
            'sleep_performance', sleep_performance,
            'strain', strain,
            'calories_active', calories_active,
            'weight_kg', weight_kg,
            'weight_delta_7d', weight_delta_7d,
            'weight_delta_30d', weight_delta_30d,
            'steps', steps
        ),
        'finance', jsonb_build_object(
            'spend_total', spend_total,
            'spend_groceries', spend_groceries,
            'spend_restaurants', spend_restaurants,
            'spend_transport', spend_transport,
            'income_total', income_total,
            'transaction_count', transaction_count,
            'spending_by_category', spending_by_category
        ),
        'nutrition', jsonb_build_object(
            'meals_logged', meals_logged,
            'water_ml', water_ml,
            'calories_consumed', calories_consumed,
            'protein_g', protein_g
        ),
        'behavior', jsonb_build_object(
            'tv_hours', tv_hours,
            'time_at_home_minutes', time_at_home_minutes,
            'sleep_detected_at', sleep_detected_at,
            'first_motion_time', first_motion_time,
            'last_motion_time', last_motion_time
        ),
        'data_quality', jsonb_build_object(
            'completeness', data_completeness,
            'computed_at', computed_at
        )
    ) INTO result
    FROM life.mv_daily_summary
    WHERE day = target_date;

    RETURN COALESCE(result, '{}'::jsonb);
END;
$$ LANGUAGE plpgsql STABLE;

-- Initial population
REFRESH MATERIALIZED VIEW life.mv_daily_summary;

COMMENT ON MATERIALIZED VIEW life.mv_daily_summary IS 'Canonical daily summary - single source of truth for all daily metrics';
COMMENT ON FUNCTION life.refresh_daily_summary(DATE) IS 'Refresh daily summary for a specific date';
COMMENT ON FUNCTION life.get_daily_summary_canonical(DATE) IS 'Get daily summary as JSONB (API-compatible format)';
