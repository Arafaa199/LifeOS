-- Migration: 004_dashboard_read_model
-- Purpose: Create dashboard read model (baselines + views) for single-payload dashboard
--
-- This creates:
--   1. life.daily_facts - unified daily row (the spine)
--   2. life.baselines - rolling 7d/30d averages
--   3. dashboard.v_today - complete dashboard payload
--   4. dashboard.v_trends - 7d/30d deltas
--   5. dashboard.v_recent_events - latest N events
--   6. ops.feed_status - last sync per source

BEGIN;

-- =============================================================================
-- Schema: life (canonical facts)
-- =============================================================================
CREATE SCHEMA IF NOT EXISTS life;
COMMENT ON SCHEMA life IS 'Canonical life facts - derived, recomputable daily summaries';

-- =============================================================================
-- life.daily_facts - The Spine (one row per Dubai day)
-- =============================================================================
CREATE TABLE life.daily_facts (
    day DATE PRIMARY KEY,

    -- Health: Recovery
    recovery_score INT,
    hrv DECIMAL(6,2),                    -- hrv_rmssd in ms
    rhr INT,                             -- resting heart rate
    spo2 DECIMAL(4,1),

    -- Health: Sleep
    sleep_minutes INT,
    deep_sleep_minutes INT,
    rem_sleep_minutes INT,
    sleep_efficiency DECIMAL(4,1),
    sleep_performance INT,

    -- Health: Strain
    strain DECIMAL(4,1),
    calories_active INT,

    -- Health: Body
    weight_kg DECIMAL(5,2),

    -- Health: Activity (placeholder for HealthKit)
    steps INT,

    -- Finance
    spend_total DECIMAL(10,2) DEFAULT 0,
    spend_groceries DECIMAL(10,2) DEFAULT 0,
    spend_restaurants DECIMAL(10,2) DEFAULT 0,
    spend_transport DECIMAL(10,2) DEFAULT 0,
    income_total DECIMAL(10,2) DEFAULT 0,
    transaction_count INT DEFAULT 0,

    -- Nutrition (early)
    meals_logged INT DEFAULT 0,
    water_ml INT DEFAULT 0,
    calories_consumed INT,
    protein_g INT,

    -- Context (optional, from HA behavioral signals)
    first_motion_time TIME,
    last_motion_time TIME,

    -- Meta
    data_completeness DECIMAL(3,2),      -- 0.00 to 1.00
    computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_daily_facts_day ON life.daily_facts(day DESC);
COMMENT ON TABLE life.daily_facts IS 'Unified daily row - the spine of the dashboard. Derived from health/finance/nutrition tables.';

-- =============================================================================
-- life.baselines - Rolling averages for "relative" insights
-- =============================================================================
CREATE MATERIALIZED VIEW life.baselines AS
WITH recent_facts AS (
    SELECT * FROM life.daily_facts
    WHERE day >= CURRENT_DATE - INTERVAL '30 days'
)
SELECT
    -- 7-day baselines
    AVG(recovery_score) FILTER (WHERE day >= CURRENT_DATE - INTERVAL '7 days') AS recovery_7d_avg,
    AVG(hrv) FILTER (WHERE day >= CURRENT_DATE - INTERVAL '7 days') AS hrv_7d_avg,
    AVG(rhr) FILTER (WHERE day >= CURRENT_DATE - INTERVAL '7 days') AS rhr_7d_avg,
    AVG(sleep_minutes) FILTER (WHERE day >= CURRENT_DATE - INTERVAL '7 days') AS sleep_minutes_7d_avg,
    AVG(strain) FILTER (WHERE day >= CURRENT_DATE - INTERVAL '7 days') AS strain_7d_avg,
    AVG(steps) FILTER (WHERE day >= CURRENT_DATE - INTERVAL '7 days') AS steps_7d_avg,
    AVG(weight_kg) FILTER (WHERE day >= CURRENT_DATE - INTERVAL '7 days') AS weight_7d_avg,
    AVG(spend_total) FILTER (WHERE day >= CURRENT_DATE - INTERVAL '7 days') AS spend_7d_avg,

    -- 7-day stddev (for "unusual day" detection)
    STDDEV(recovery_score) FILTER (WHERE day >= CURRENT_DATE - INTERVAL '7 days') AS recovery_7d_stddev,
    STDDEV(sleep_minutes) FILTER (WHERE day >= CURRENT_DATE - INTERVAL '7 days') AS sleep_minutes_7d_stddev,
    STDDEV(spend_total) FILTER (WHERE day >= CURRENT_DATE - INTERVAL '7 days') AS spend_7d_stddev,

    -- 30-day baselines
    AVG(recovery_score) AS recovery_30d_avg,
    AVG(hrv) AS hrv_30d_avg,
    AVG(rhr) AS rhr_30d_avg,
    AVG(sleep_minutes) AS sleep_minutes_30d_avg,
    AVG(strain) AS strain_30d_avg,
    AVG(steps) AS steps_30d_avg,
    AVG(weight_kg) AS weight_30d_avg,
    AVG(spend_total) AS spend_30d_avg,

    -- 30-day stddev
    STDDEV(recovery_score) AS recovery_30d_stddev,
    STDDEV(sleep_minutes) AS sleep_minutes_30d_stddev,
    STDDEV(spend_total) AS spend_30d_stddev,

    -- Weight trend (first vs last in 30d)
    (SELECT weight_kg FROM recent_facts WHERE weight_kg IS NOT NULL ORDER BY day DESC LIMIT 1) -
    (SELECT weight_kg FROM recent_facts WHERE weight_kg IS NOT NULL ORDER BY day ASC LIMIT 1) AS weight_30d_delta,

    -- Meta
    COUNT(*) FILTER (WHERE day >= CURRENT_DATE - INTERVAL '7 days') AS days_with_data_7d,
    COUNT(*) AS days_with_data_30d,
    NOW() AS computed_at
FROM recent_facts;

COMMENT ON MATERIALIZED VIEW life.baselines IS 'Rolling 7d/30d averages for relative comparisons. Refresh daily or on-demand.';

-- =============================================================================
-- Schema: dashboard (read model views)
-- =============================================================================
CREATE SCHEMA IF NOT EXISTS dashboard;
COMMENT ON SCHEMA dashboard IS 'Dashboard read model - views for single-payload dashboard';

-- =============================================================================
-- dashboard.v_today - Complete today payload
-- =============================================================================
CREATE OR REPLACE VIEW dashboard.v_today AS
SELECT
    -- Today's facts
    f.day,
    f.recovery_score,
    f.hrv,
    f.rhr,
    f.sleep_minutes,
    f.deep_sleep_minutes,
    f.rem_sleep_minutes,
    f.sleep_efficiency,
    f.strain,
    f.steps,
    f.weight_kg,
    f.spend_total,
    f.spend_groceries,
    f.spend_restaurants,
    f.income_total,
    f.transaction_count,
    f.meals_logged,
    f.water_ml,
    f.calories_consumed,
    f.data_completeness,

    -- Deltas vs baseline
    f.recovery_score - b.recovery_7d_avg AS recovery_vs_7d,
    f.recovery_score - b.recovery_30d_avg AS recovery_vs_30d,
    f.hrv - b.hrv_7d_avg AS hrv_vs_7d,
    f.sleep_minutes - b.sleep_minutes_7d_avg AS sleep_vs_7d,
    f.strain - b.strain_7d_avg AS strain_vs_7d,
    f.spend_total - b.spend_7d_avg AS spend_vs_7d,
    f.weight_kg - b.weight_7d_avg AS weight_vs_7d,

    -- Is today unusual? (> 1.5 stddev from mean)
    CASE WHEN b.recovery_7d_stddev > 0 AND
         ABS(f.recovery_score - b.recovery_7d_avg) > 1.5 * b.recovery_7d_stddev
         THEN TRUE ELSE FALSE END AS recovery_unusual,
    CASE WHEN b.sleep_minutes_7d_stddev > 0 AND
         ABS(f.sleep_minutes - b.sleep_minutes_7d_avg) > 1.5 * b.sleep_minutes_7d_stddev
         THEN TRUE ELSE FALSE END AS sleep_unusual,
    CASE WHEN b.spend_7d_stddev > 0 AND
         ABS(f.spend_total - b.spend_7d_avg) > 1.5 * b.spend_7d_stddev
         THEN TRUE ELSE FALSE END AS spend_unusual,

    -- Baselines for reference
    b.recovery_7d_avg,
    b.recovery_30d_avg,
    b.hrv_7d_avg,
    b.sleep_minutes_7d_avg,
    b.weight_30d_delta,
    b.days_with_data_7d,
    b.days_with_data_30d

FROM life.daily_facts f
CROSS JOIN life.baselines b
WHERE f.day = (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Dubai')::date;

COMMENT ON VIEW dashboard.v_today IS 'Today facts + baselines + deltas. The main dashboard payload.';

-- =============================================================================
-- dashboard.v_trends - 7d and 30d trends
-- =============================================================================
CREATE OR REPLACE VIEW dashboard.v_trends AS
SELECT
    '7d' AS period,
    AVG(recovery_score) AS avg_recovery,
    AVG(hrv) AS avg_hrv,
    AVG(rhr) AS avg_rhr,
    AVG(sleep_minutes) AS avg_sleep_minutes,
    AVG(strain) AS avg_strain,
    AVG(steps) AS avg_steps,
    SUM(spend_total) AS total_spend,
    AVG(spend_total) AS avg_daily_spend,
    MAX(weight_kg) - MIN(weight_kg) AS weight_range,
    (SELECT weight_kg FROM life.daily_facts WHERE weight_kg IS NOT NULL ORDER BY day DESC LIMIT 1) AS latest_weight
FROM life.daily_facts
WHERE day >= CURRENT_DATE - INTERVAL '7 days'

UNION ALL

SELECT
    '30d' AS period,
    AVG(recovery_score) AS avg_recovery,
    AVG(hrv) AS avg_hrv,
    AVG(rhr) AS avg_rhr,
    AVG(sleep_minutes) AS avg_sleep_minutes,
    AVG(strain) AS avg_strain,
    AVG(steps) AS avg_steps,
    SUM(spend_total) AS total_spend,
    AVG(spend_total) AS avg_daily_spend,
    MAX(weight_kg) - MIN(weight_kg) AS weight_range,
    (SELECT weight_kg FROM life.daily_facts WHERE weight_kg IS NOT NULL ORDER BY day DESC LIMIT 1) AS latest_weight
FROM life.daily_facts
WHERE day >= CURRENT_DATE - INTERVAL '30 days';

COMMENT ON VIEW dashboard.v_trends IS '7d and 30d aggregate trends for the trend cards.';

-- =============================================================================
-- dashboard.v_recent_events - Latest N events per type
-- =============================================================================
CREATE OR REPLACE VIEW dashboard.v_recent_events AS
-- Recent transactions
SELECT
    'transaction' AS event_type,
    t.date AS event_date,
    t.date::timestamp AS event_time,
    jsonb_build_object(
        'merchant', t.merchant_name,
        'amount', t.amount,
        'category', t.category
    ) AS payload
FROM finance.transactions t
WHERE t.date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY t.date DESC
LIMIT 10;

-- Note: Add more event types as sources are unified:
-- UNION ALL SELECT 'weigh_in', ... FROM health.metrics WHERE metric_type = 'weight'
-- UNION ALL SELECT 'sleep', ... FROM health.whoop_sleep

COMMENT ON VIEW dashboard.v_recent_events IS 'Latest events for the dashboard timeline. Add more event types as needed.';

-- =============================================================================
-- Schema: ops (operational views)
-- =============================================================================
CREATE SCHEMA IF NOT EXISTS ops;
COMMENT ON SCHEMA ops IS 'Operational monitoring - feed status, ingestion health';

-- =============================================================================
-- ops.feed_status - Last sync per source
-- =============================================================================
CREATE OR REPLACE VIEW ops.feed_status AS
SELECT
    'whoop_recovery' AS feed,
    MAX(created_at) AS last_sync,
    EXTRACT(EPOCH FROM (NOW() - MAX(created_at)))/3600 AS hours_since_sync,
    CASE
        WHEN MAX(created_at) > NOW() - INTERVAL '6 hours' THEN 'healthy'
        WHEN MAX(created_at) > NOW() - INTERVAL '24 hours' THEN 'stale'
        ELSE 'critical'
    END AS status,
    COUNT(*) AS total_records
FROM health.whoop_recovery

UNION ALL

SELECT
    'whoop_sleep' AS feed,
    MAX(created_at) AS last_sync,
    EXTRACT(EPOCH FROM (NOW() - MAX(created_at)))/3600 AS hours_since_sync,
    CASE
        WHEN MAX(created_at) > NOW() - INTERVAL '6 hours' THEN 'healthy'
        WHEN MAX(created_at) > NOW() - INTERVAL '24 hours' THEN 'stale'
        ELSE 'critical'
    END AS status,
    COUNT(*) AS total_records
FROM health.whoop_sleep

UNION ALL

SELECT
    'whoop_strain' AS feed,
    MAX(created_at) AS last_sync,
    EXTRACT(EPOCH FROM (NOW() - MAX(created_at)))/3600 AS hours_since_sync,
    CASE
        WHEN MAX(created_at) > NOW() - INTERVAL '6 hours' THEN 'healthy'
        WHEN MAX(created_at) > NOW() - INTERVAL '24 hours' THEN 'stale'
        ELSE 'critical'
    END AS status,
    COUNT(*) AS total_records
FROM health.whoop_strain

UNION ALL

SELECT
    'weight' AS feed,
    MAX(recorded_at) AS last_sync,
    EXTRACT(EPOCH FROM (NOW() - MAX(recorded_at)))/3600 AS hours_since_sync,
    CASE
        WHEN MAX(recorded_at) > NOW() - INTERVAL '24 hours' THEN 'healthy'
        WHEN MAX(recorded_at) > NOW() - INTERVAL '72 hours' THEN 'stale'
        ELSE 'critical'
    END AS status,
    COUNT(*) AS total_records
FROM health.metrics WHERE metric_type = 'weight'

UNION ALL

SELECT
    'transactions' AS feed,
    MAX(created_at) AS last_sync,
    EXTRACT(EPOCH FROM (NOW() - MAX(created_at)))/3600 AS hours_since_sync,
    CASE
        WHEN MAX(created_at) > NOW() - INTERVAL '24 hours' THEN 'healthy'
        WHEN MAX(created_at) > NOW() - INTERVAL '72 hours' THEN 'stale'
        ELSE 'critical'
    END AS status,
    COUNT(*) AS total_records
FROM finance.transactions;

COMMENT ON VIEW ops.feed_status IS 'Data freshness per source. Used for stale-feed banners.';

-- =============================================================================
-- Function: life.refresh_daily_facts(target_day DATE)
-- Recompute a single day's facts from source tables
-- =============================================================================
CREATE OR REPLACE FUNCTION life.refresh_daily_facts(target_day DATE DEFAULT NULL)
RETURNS void AS $$
DECLARE
    the_day DATE := COALESCE(target_day, (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Dubai')::date);
BEGIN
    INSERT INTO life.daily_facts (
        day,
        -- Health: Recovery
        recovery_score, hrv, rhr, spo2,
        -- Health: Sleep
        sleep_minutes, deep_sleep_minutes, rem_sleep_minutes, sleep_efficiency, sleep_performance,
        -- Health: Strain
        strain, calories_active,
        -- Health: Body
        weight_kg,
        -- Finance
        spend_total, spend_groceries, spend_restaurants, spend_transport, income_total, transaction_count,
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
        -- Sleep (from health.whoop_sleep)
        s.time_in_bed_min - COALESCE(s.awake_min, 0),  -- actual sleep minutes
        s.deep_sleep_min,
        s.rem_sleep_min,
        s.sleep_efficiency,
        s.sleep_performance,
        -- Strain (from health.whoop_strain)
        st.day_strain,
        st.calories_active,
        -- Weight (latest from health.metrics)
        (SELECT value FROM health.metrics
         WHERE metric_type = 'weight' AND recorded_at::date = the_day
         ORDER BY recorded_at DESC LIMIT 1),
        -- Finance (from finance.transactions)
        COALESCE(ABS(SUM(CASE WHEN t.amount < 0 THEN t.amount ELSE 0 END)), 0),
        COALESCE(ABS(SUM(CASE WHEN t.amount < 0 AND t.category = 'Groceries' THEN t.amount ELSE 0 END)), 0),
        COALESCE(ABS(SUM(CASE WHEN t.amount < 0 AND t.category IN ('Dining', 'Restaurants', 'Food Delivery') THEN t.amount ELSE 0 END)), 0),
        COALESCE(ABS(SUM(CASE WHEN t.amount < 0 AND t.category = 'Transport' THEN t.amount ELSE 0 END)), 0),
        COALESCE(SUM(CASE WHEN t.amount > 0 THEN t.amount ELSE 0 END), 0),
        COUNT(t.id),
        -- Nutrition (from nutrition.food_log if exists, else from core.daily_summary)
        COALESCE(ds.meals_logged, 0),
        COALESCE(ds.water_ml, 0),
        ds.calories_consumed,
        ds.protein_g,
        -- Data completeness score
        (
            CASE WHEN r.recovery_score IS NOT NULL THEN 0.2 ELSE 0 END +
            CASE WHEN s.time_in_bed_min IS NOT NULL THEN 0.2 ELSE 0 END +
            CASE WHEN st.day_strain IS NOT NULL THEN 0.15 ELSE 0 END +
            CASE WHEN EXISTS (SELECT 1 FROM health.metrics WHERE metric_type = 'weight' AND recorded_at::date = the_day) THEN 0.15 ELSE 0 END +
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
        strain = EXCLUDED.strain,
        calories_active = EXCLUDED.calories_active,
        weight_kg = EXCLUDED.weight_kg,
        spend_total = EXCLUDED.spend_total,
        spend_groceries = EXCLUDED.spend_groceries,
        spend_restaurants = EXCLUDED.spend_restaurants,
        spend_transport = EXCLUDED.spend_transport,
        income_total = EXCLUDED.income_total,
        transaction_count = EXCLUDED.transaction_count,
        meals_logged = EXCLUDED.meals_logged,
        water_ml = EXCLUDED.water_ml,
        calories_consumed = EXCLUDED.calories_consumed,
        protein_g = EXCLUDED.protein_g,
        data_completeness = EXCLUDED.data_completeness,
        computed_at = NOW();
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION life.refresh_daily_facts IS 'Recompute facts for a single day. Idempotent - safe to re-run.';

-- =============================================================================
-- Function: life.refresh_baselines()
-- Refresh the baselines materialized view
-- =============================================================================
CREATE OR REPLACE FUNCTION life.refresh_baselines()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW life.baselines;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION life.refresh_baselines IS 'Refresh the rolling baselines. Call after refreshing daily_facts.';

-- =============================================================================
-- Function: life.refresh_all(days_back INT)
-- Refresh last N days of facts + baselines
-- =============================================================================
CREATE OR REPLACE FUNCTION life.refresh_all(days_back INT DEFAULT 7)
RETURNS void AS $$
DECLARE
    d DATE;
BEGIN
    FOR d IN SELECT generate_series(
        (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Dubai')::date - days_back,
        (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Dubai')::date,
        '1 day'::interval
    )::date
    LOOP
        PERFORM life.refresh_daily_facts(d);
    END LOOP;

    PERFORM life.refresh_baselines();
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION life.refresh_all IS 'Refresh last N days of facts + baselines. Use for backfill or nightly job.';

COMMIT;
