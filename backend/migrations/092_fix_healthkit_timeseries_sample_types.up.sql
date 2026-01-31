-- Fix facts.v_daily_health_timeseries to accept both short names and full HK identifiers
-- iOS sends full HK identifiers (e.g., HKQuantityTypeIdentifierStepCount)
-- but the view was filtering for short names only (e.g., 'steps')

CREATE OR REPLACE VIEW facts.v_daily_health_timeseries AS
WITH healthkit_steps AS (
    SELECT (start_date AT TIME ZONE 'Asia/Dubai')::date AS date,
           COALESCE(SUM(value), 0)::integer AS steps
    FROM raw.healthkit_samples
    WHERE sample_type IN ('steps', 'HKQuantityTypeIdentifierStepCount')
    GROUP BY (start_date AT TIME ZONE 'Asia/Dubai')::date
), healthkit_active_energy AS (
    SELECT (start_date AT TIME ZONE 'Asia/Dubai')::date AS date,
           COALESCE(SUM(value), 0)::integer AS active_energy
    FROM raw.healthkit_samples
    WHERE sample_type IN ('active_energy', 'HKQuantityTypeIdentifierActiveEnergyBurned')
    GROUP BY (start_date AT TIME ZONE 'Asia/Dubai')::date
), healthkit_weight_raw AS (
    SELECT DISTINCT ON ((start_date AT TIME ZONE 'Asia/Dubai')::date)
           (start_date AT TIME ZONE 'Asia/Dubai')::date AS date,
           value AS weight_kg
    FROM raw.healthkit_samples
    WHERE sample_type IN ('weight', 'HKQuantityTypeIdentifierBodyMass')
    ORDER BY (start_date AT TIME ZONE 'Asia/Dubai')::date, start_date DESC
), healthkit_weight_legacy AS (
    SELECT DISTINCT ON (date) date, value AS weight_kg
    FROM health.metrics
    WHERE metric_type = 'weight'
    ORDER BY date, recorded_at DESC
), healthkit_weight AS (
    SELECT COALESCE(r.date, l.date) AS date,
           COALESCE(r.weight_kg, l.weight_kg) AS weight_kg
    FROM healthkit_weight_raw r
    FULL JOIN healthkit_weight_legacy l ON r.date = l.date
), date_series AS (
    SELECT generate_series(CURRENT_DATE - INTERVAL '90 days', CURRENT_DATE, '1 day')::date AS date
)
SELECT ds.date,
       dr.hrv,
       dr.rhr,
       dr.recovery_score AS recovery,
       dsl.total_sleep_min AS sleep_minutes,
       dsl.sleep_performance AS sleep_quality,
       dst.day_strain AS strain,
       COALESCE(hs.steps, 0) AS steps,
       hw.weight_kg AS weight,
       COALESCE(hae.active_energy, 0) AS active_energy,
       ROUND((
           CASE WHEN dr.recovery_score IS NOT NULL THEN 1 ELSE 0 END +
           CASE WHEN dr.hrv IS NOT NULL THEN 1 ELSE 0 END +
           CASE WHEN dsl.total_sleep_min IS NOT NULL THEN 1 ELSE 0 END +
           CASE WHEN dst.day_strain IS NOT NULL THEN 1 ELSE 0 END +
           CASE WHEN hs.steps > 0 THEN 1 ELSE 0 END +
           CASE WHEN hw.weight_kg IS NOT NULL THEN 1 ELSE 0 END
       )::numeric / 6.0, 2) AS coverage
FROM date_series ds
LEFT JOIN normalized.daily_recovery dr ON dr.date = ds.date
LEFT JOIN normalized.daily_sleep dsl ON dsl.date = ds.date
LEFT JOIN normalized.daily_strain dst ON dst.date = ds.date
LEFT JOIN healthkit_steps hs ON hs.date = ds.date
LEFT JOIN healthkit_active_energy hae ON hae.date = ds.date
LEFT JOIN healthkit_weight hw ON hw.date = ds.date
ORDER BY ds.date DESC;
