-- Migration: 077_health_timeseries
-- Purpose: Create view for daily health time series with HealthKit data
-- Supports: GET /webhook/nexus-health-timeseries?days=7|14|30
--
-- Data sources:
-- - WHOOP: recovery, HRV, RHR, sleep, strain from normalized tables
-- - HealthKit: steps, active_energy from raw.healthkit_samples
-- - Weight: from health.metrics (legacy) OR raw.healthkit_samples
-- - Coverage: fraction of data points present

BEGIN;

-- =============================================================================
-- facts.v_daily_health_timeseries - Daily health data with HealthKit metrics
-- =============================================================================
-- This view provides daily health metrics for the iOS HealthTrendsView.
-- It joins WHOOP data from normalized tables with HealthKit aggregates.

CREATE OR REPLACE VIEW facts.v_daily_health_timeseries AS
WITH
-- Aggregate HealthKit steps by date (Dubai timezone)
healthkit_steps AS (
    SELECT
        (start_date AT TIME ZONE 'Asia/Dubai')::date AS date,
        COALESCE(SUM(value), 0)::int AS steps
    FROM raw.healthkit_samples
    WHERE sample_type = 'steps'
    GROUP BY 1
),
-- Aggregate HealthKit active energy by date
healthkit_active_energy AS (
    SELECT
        (start_date AT TIME ZONE 'Asia/Dubai')::date AS date,
        COALESCE(SUM(value), 0)::int AS active_energy
    FROM raw.healthkit_samples
    WHERE sample_type = 'active_energy'
    GROUP BY 1
),
-- Get latest weight per day from raw.healthkit_samples (new path)
healthkit_weight_raw AS (
    SELECT DISTINCT ON ((start_date AT TIME ZONE 'Asia/Dubai')::date)
        (start_date AT TIME ZONE 'Asia/Dubai')::date AS date,
        value AS weight_kg
    FROM raw.healthkit_samples
    WHERE sample_type = 'weight'
    ORDER BY (start_date AT TIME ZONE 'Asia/Dubai')::date, start_date DESC
),
-- Get latest weight per day from health.metrics (legacy path)
healthkit_weight_legacy AS (
    SELECT DISTINCT ON (date)
        date,
        value AS weight_kg
    FROM health.metrics
    WHERE metric_type = 'weight'
    ORDER BY date, recorded_at DESC
),
-- Merge both weight sources (prefer raw if both exist)
healthkit_weight AS (
    SELECT
        COALESCE(r.date, l.date) AS date,
        COALESCE(r.weight_kg, l.weight_kg) AS weight_kg
    FROM healthkit_weight_raw r
    FULL OUTER JOIN healthkit_weight_legacy l ON r.date = l.date
),
-- Generate date series for the last 90 days
date_series AS (
    SELECT generate_series(
        CURRENT_DATE - INTERVAL '90 days',
        CURRENT_DATE,
        INTERVAL '1 day'
    )::date AS date
)
SELECT
    ds.date,
    -- WHOOP Recovery data
    dr.hrv,
    dr.rhr,
    dr.recovery_score AS recovery,
    -- WHOOP Sleep data (in minutes for iOS compatibility)
    dsl.total_sleep_min AS sleep_minutes,
    dsl.sleep_performance AS sleep_quality,
    -- WHOOP Strain data
    dst.day_strain AS strain,
    -- HealthKit data
    COALESCE(hs.steps, 0) AS steps,
    hw.weight_kg AS weight,
    COALESCE(hae.active_energy, 0) AS active_energy,
    -- Data coverage calculation (6 possible data points)
    ROUND((
        (CASE WHEN dr.recovery_score IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN dr.hrv IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN dsl.total_sleep_min IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN dst.day_strain IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN hs.steps > 0 THEN 1 ELSE 0 END) +
        (CASE WHEN hw.weight_kg IS NOT NULL THEN 1 ELSE 0 END)
    )::numeric / 6.0, 2) AS coverage
FROM date_series ds
LEFT JOIN normalized.daily_recovery dr ON dr.date = ds.date
LEFT JOIN normalized.daily_sleep dsl ON dsl.date = ds.date
LEFT JOIN normalized.daily_strain dst ON dst.date = ds.date
LEFT JOIN healthkit_steps hs ON hs.date = ds.date
LEFT JOIN healthkit_active_energy hae ON hae.date = ds.date
LEFT JOIN healthkit_weight hw ON hw.date = ds.date
ORDER BY ds.date DESC;

COMMENT ON VIEW facts.v_daily_health_timeseries IS 'Daily health time series combining WHOOP and HealthKit data for iOS HealthTrendsView';

-- =============================================================================
-- facts.get_health_timeseries(days INT) - Function to get time series data
-- =============================================================================
-- Returns JSON array of daily health data for the specified number of days.
-- Used by n8n webhook to serve iOS app requests.

CREATE OR REPLACE FUNCTION facts.get_health_timeseries(days_requested INT DEFAULT 30)
RETURNS JSONB AS $$
BEGIN
    RETURN (
        SELECT jsonb_agg(row_to_json(t))
        FROM (
            SELECT
                date,
                hrv,
                rhr,
                recovery,
                sleep_minutes,
                sleep_quality,
                strain,
                steps,
                weight,
                active_energy,
                coverage
            FROM facts.v_daily_health_timeseries
            WHERE date >= CURRENT_DATE - (days_requested - 1)
              AND date <= CURRENT_DATE
            ORDER BY date ASC
        ) t
    );
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION facts.get_health_timeseries(INT) IS 'Returns daily health time series as JSON array for specified number of days';

-- =============================================================================
-- Backfill: Ensure normalized tables have data from raw tables
-- =============================================================================
-- This ensures any raw WHOOP data that hasn't been normalized gets processed.

-- Backfill daily_recovery from raw.whoop_cycles
INSERT INTO normalized.daily_recovery (
    date, recovery_score, hrv, rhr, spo2, skin_temp_c,
    source, updated_at
)
SELECT
    date,
    recovery_score,
    hrv,
    rhr,
    spo2,
    skin_temp,
    'whoop',
    NOW()
FROM raw.whoop_cycles
WHERE recovery_score IS NOT NULL
ON CONFLICT (date) DO UPDATE SET
    recovery_score = EXCLUDED.recovery_score,
    hrv = EXCLUDED.hrv,
    rhr = EXCLUDED.rhr,
    spo2 = EXCLUDED.spo2,
    skin_temp_c = EXCLUDED.skin_temp_c,
    updated_at = NOW();

-- Backfill daily_sleep from raw.whoop_sleep
INSERT INTO normalized.daily_sleep (
    date, total_sleep_min, light_sleep_min, deep_sleep_min, rem_sleep_min,
    awake_min, time_in_bed_min, sleep_efficiency, sleep_performance,
    respiratory_rate, source, updated_at
)
SELECT
    date,
    ROUND((COALESCE(light_sleep_ms, 0) + COALESCE(deep_sleep_ms, 0) + COALESCE(rem_sleep_ms, 0)) / 60000.0)::int,
    ROUND(COALESCE(light_sleep_ms, 0) / 60000.0)::int,
    ROUND(COALESCE(deep_sleep_ms, 0) / 60000.0)::int,
    ROUND(COALESCE(rem_sleep_ms, 0) / 60000.0)::int,
    ROUND(COALESCE(awake_ms, 0) / 60000.0)::int,
    ROUND(COALESCE(time_in_bed_ms, 0) / 60000.0)::int,
    sleep_efficiency,
    sleep_performance,
    respiratory_rate,
    'whoop',
    NOW()
FROM raw.whoop_sleep
WHERE sleep_id IS NOT NULL
ON CONFLICT (date) DO UPDATE SET
    total_sleep_min = EXCLUDED.total_sleep_min,
    light_sleep_min = EXCLUDED.light_sleep_min,
    deep_sleep_min = EXCLUDED.deep_sleep_min,
    rem_sleep_min = EXCLUDED.rem_sleep_min,
    awake_min = EXCLUDED.awake_min,
    time_in_bed_min = EXCLUDED.time_in_bed_min,
    sleep_efficiency = EXCLUDED.sleep_efficiency,
    sleep_performance = EXCLUDED.sleep_performance,
    respiratory_rate = EXCLUDED.respiratory_rate,
    updated_at = NOW();

-- Backfill daily_strain from raw.whoop_strain
INSERT INTO normalized.daily_strain (
    date, day_strain, calories_burned, workout_count, average_hr, max_hr,
    source, updated_at
)
SELECT
    date,
    day_strain,
    ROUND(COALESCE(kilojoules, 0) / 4.184)::int,  -- Convert kJ to kcal
    workout_count,
    average_hr,
    max_hr,
    'whoop',
    NOW()
FROM raw.whoop_strain
WHERE strain_id IS NOT NULL
ON CONFLICT (date) DO UPDATE SET
    day_strain = EXCLUDED.day_strain,
    calories_burned = EXCLUDED.calories_burned,
    workout_count = EXCLUDED.workout_count,
    average_hr = EXCLUDED.average_hr,
    max_hr = EXCLUDED.max_hr,
    updated_at = NOW();

-- Refresh facts.daily_health for last 30 days
DO $$
DECLARE
    iter_date DATE;
BEGIN
    iter_date := CURRENT_DATE - 29;
    WHILE iter_date <= CURRENT_DATE LOOP
        PERFORM facts.refresh_daily_health(iter_date);
        iter_date := iter_date + 1;
    END LOOP;
END $$;

COMMIT;
