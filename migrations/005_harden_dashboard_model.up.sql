-- Migration: 005_harden_dashboard_model
-- Purpose: Add idempotency, locking, logging, timezone enforcement, and API contract
--
-- Improvements:
--   1. Advisory lock to prevent concurrent refreshes
--   2. Explicit Asia/Dubai timezone everywhere
--   3. Refresh log for debuggability
--   4. Versioned API payload with metadata
--   5. Clear recompute rules (today + yesterday default)

BEGIN;

-- =============================================================================
-- Drop old functions from 004 (different signatures)
-- =============================================================================
DROP FUNCTION IF EXISTS life.refresh_daily_facts(DATE);
DROP FUNCTION IF EXISTS life.refresh_baselines();
DROP FUNCTION IF EXISTS life.refresh_all(INT);

-- =============================================================================
-- ops.refresh_log - Debuggability for refresh operations
-- =============================================================================
CREATE TABLE IF NOT EXISTS ops.refresh_log (
    id SERIAL PRIMARY KEY,
    run_id UUID NOT NULL DEFAULT gen_random_uuid(),
    operation VARCHAR(50) NOT NULL,        -- 'refresh_daily_facts', 'refresh_baselines', 'refresh_all'
    target_day DATE,                       -- NULL for baselines
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    duration_ms INT,
    rows_affected INT DEFAULT 0,
    status VARCHAR(20) DEFAULT 'running',  -- 'running', 'success', 'skipped', 'error'
    error_message TEXT,
    warnings JSONB,
    triggered_by VARCHAR(50)               -- 'n8n_nightly', 'manual', 'webhook'
);

CREATE INDEX idx_refresh_log_started ON ops.refresh_log(started_at DESC);
CREATE INDEX idx_refresh_log_status ON ops.refresh_log(status) WHERE status != 'success';

COMMENT ON TABLE ops.refresh_log IS 'Audit log for all refresh operations. Check here when "why didn''t it update?"';

-- =============================================================================
-- Timezone constant - Use this everywhere
-- =============================================================================
-- We store dates in Dubai local time (Asia/Dubai = UTC+4)
-- All day boundaries are computed in this timezone

-- Helper function to get current Dubai date
CREATE OR REPLACE FUNCTION life.dubai_today()
RETURNS DATE AS $$
    SELECT (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Dubai')::date;
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION life.dubai_today IS 'Current date in Asia/Dubai timezone. Use this instead of CURRENT_DATE.';

-- Helper function to convert timestamp to Dubai date
CREATE OR REPLACE FUNCTION life.to_dubai_date(ts TIMESTAMPTZ)
RETURNS DATE AS $$
    SELECT (ts AT TIME ZONE 'Asia/Dubai')::date;
$$ LANGUAGE sql IMMUTABLE;

COMMENT ON FUNCTION life.to_dubai_date IS 'Convert any timestamp to Dubai local date.';

-- =============================================================================
-- Hardened refresh_daily_facts with locking and logging
-- =============================================================================
CREATE OR REPLACE FUNCTION life.refresh_daily_facts(
    target_day DATE DEFAULT NULL,
    triggered_by VARCHAR(50) DEFAULT 'manual'
)
RETURNS TABLE(status TEXT, rows_affected INT, duration_ms INT) AS $$
DECLARE
    the_day DATE;
    lock_id BIGINT;
    start_time TIMESTAMPTZ;
    end_time TIMESTAMPTZ;
    affected INT;
    log_id INT;
    run_uuid UUID;
BEGIN
    -- Use Dubai today if no target specified
    the_day := COALESCE(target_day, life.dubai_today());

    -- Lock ID based on date (different days can run in parallel)
    lock_id := ('x' || md5('refresh_daily_facts_' || the_day::text))::bit(32)::int;

    -- Try to acquire advisory lock (non-blocking)
    IF NOT pg_try_advisory_lock(lock_id) THEN
        -- Another process is refreshing this day
        RETURN QUERY SELECT 'skipped'::TEXT, 0, 0;
        RETURN;
    END IF;

    -- Start logging
    run_uuid := gen_random_uuid();
    start_time := clock_timestamp();

    INSERT INTO ops.refresh_log (run_id, operation, target_day, triggered_by)
    VALUES (run_uuid, 'refresh_daily_facts', the_day, triggered_by)
    RETURNING id INTO log_id;

    BEGIN
        -- Perform the actual refresh
        INSERT INTO life.daily_facts (
            day,
            recovery_score, hrv, rhr, spo2,
            sleep_minutes, deep_sleep_minutes, rem_sleep_minutes, sleep_efficiency, sleep_performance,
            strain, calories_active,
            weight_kg,
            spend_total, spend_groceries, spend_restaurants, spend_transport, income_total, transaction_count,
            meals_logged, water_ml, calories_consumed, protein_g,
            data_completeness, computed_at
        )
        SELECT
            the_day,
            r.recovery_score,
            r.hrv_rmssd,
            r.rhr,
            r.spo2,
            s.time_in_bed_min - COALESCE(s.awake_min, 0),
            s.deep_sleep_min,
            s.rem_sleep_min,
            s.sleep_efficiency,
            s.sleep_performance,
            st.day_strain,
            st.calories_active,
            (SELECT value FROM health.metrics
             WHERE metric_type = 'weight'
               AND life.to_dubai_date(recorded_at) = the_day
             ORDER BY recorded_at DESC LIMIT 1),
            COALESCE(ABS(SUM(CASE WHEN t.amount < 0 THEN t.amount ELSE 0 END)), 0),
            COALESCE(ABS(SUM(CASE WHEN t.amount < 0 AND t.category = 'Groceries' THEN t.amount ELSE 0 END)), 0),
            COALESCE(ABS(SUM(CASE WHEN t.amount < 0 AND t.category IN ('Dining', 'Restaurants', 'Food Delivery') THEN t.amount ELSE 0 END)), 0),
            COALESCE(ABS(SUM(CASE WHEN t.amount < 0 AND t.category = 'Transport' THEN t.amount ELSE 0 END)), 0),
            COALESCE(SUM(CASE WHEN t.amount > 0 THEN t.amount ELSE 0 END), 0),
            COUNT(t.id),
            COALESCE(ds.meals_logged, 0),
            COALESCE(ds.water_ml, 0),
            ds.calories_consumed,
            ds.protein_g,
            (
                CASE WHEN r.recovery_score IS NOT NULL THEN 0.2 ELSE 0 END +
                CASE WHEN s.time_in_bed_min IS NOT NULL THEN 0.2 ELSE 0 END +
                CASE WHEN st.day_strain IS NOT NULL THEN 0.15 ELSE 0 END +
                CASE WHEN EXISTS (SELECT 1 FROM health.metrics WHERE metric_type = 'weight' AND life.to_dubai_date(recorded_at) = the_day) THEN 0.15 ELSE 0 END +
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

        GET DIAGNOSTICS affected = ROW_COUNT;
        end_time := clock_timestamp();

        -- Update log with success
        UPDATE ops.refresh_log
        SET ended_at = end_time,
            duration_ms = EXTRACT(MILLISECONDS FROM (end_time - start_time))::int,
            rows_affected = affected,
            status = 'success'
        WHERE id = log_id;

        -- Release lock
        PERFORM pg_advisory_unlock(lock_id);

        RETURN QUERY SELECT 'success'::TEXT, affected, EXTRACT(MILLISECONDS FROM (end_time - start_time))::int;

    EXCEPTION WHEN OTHERS THEN
        -- Log error
        UPDATE ops.refresh_log
        SET ended_at = clock_timestamp(),
            status = 'error',
            error_message = SQLERRM
        WHERE id = log_id;

        -- Release lock
        PERFORM pg_advisory_unlock(lock_id);

        RAISE;
    END;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION life.refresh_daily_facts IS 'Refresh facts for a single day. Uses advisory lock to prevent concurrent runs. Logs all operations.';

-- =============================================================================
-- Hardened refresh_baselines with locking
-- =============================================================================
CREATE OR REPLACE FUNCTION life.refresh_baselines(
    triggered_by VARCHAR(50) DEFAULT 'manual'
)
RETURNS TABLE(status TEXT, duration_ms INT) AS $$
DECLARE
    lock_id BIGINT := 999999;  -- Fixed lock ID for baselines
    start_time TIMESTAMPTZ;
    end_time TIMESTAMPTZ;
    log_id INT;
    run_uuid UUID;
BEGIN
    -- Try to acquire advisory lock
    IF NOT pg_try_advisory_lock(lock_id) THEN
        RETURN QUERY SELECT 'skipped'::TEXT, 0;
        RETURN;
    END IF;

    run_uuid := gen_random_uuid();
    start_time := clock_timestamp();

    INSERT INTO ops.refresh_log (run_id, operation, triggered_by)
    VALUES (run_uuid, 'refresh_baselines', triggered_by)
    RETURNING id INTO log_id;

    BEGIN
        REFRESH MATERIALIZED VIEW life.baselines;

        end_time := clock_timestamp();

        UPDATE ops.refresh_log
        SET ended_at = end_time,
            duration_ms = EXTRACT(MILLISECONDS FROM (end_time - start_time))::int,
            rows_affected = 1,
            status = 'success'
        WHERE id = log_id;

        PERFORM pg_advisory_unlock(lock_id);

        RETURN QUERY SELECT 'success'::TEXT, EXTRACT(MILLISECONDS FROM (end_time - start_time))::int;

    EXCEPTION WHEN OTHERS THEN
        UPDATE ops.refresh_log
        SET ended_at = clock_timestamp(),
            status = 'error',
            error_message = SQLERRM
        WHERE id = log_id;

        PERFORM pg_advisory_unlock(lock_id);
        RAISE;
    END;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- Hardened refresh_all with clear recompute rules
-- =============================================================================
CREATE OR REPLACE FUNCTION life.refresh_all(
    days_back INT DEFAULT 2,              -- Default: today + yesterday (for late data)
    triggered_by VARCHAR(50) DEFAULT 'manual'
)
RETURNS TABLE(day DATE, status TEXT, rows_affected INT, duration_ms INT) AS $$
DECLARE
    d DATE;
    result RECORD;
    today_dubai DATE := life.dubai_today();
BEGIN
    -- Recompute each day (today - days_back to today)
    FOR d IN SELECT generate_series(
        today_dubai - days_back,
        today_dubai,
        '1 day'::interval
    )::date
    LOOP
        SELECT * INTO result FROM life.refresh_daily_facts(d, triggered_by);
        RETURN QUERY SELECT d, result.status, result.rows_affected, result.duration_ms;
    END LOOP;

    -- Refresh baselines after facts
    PERFORM life.refresh_baselines(triggered_by);

    RETURN;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION life.refresh_all IS 'Refresh last N days of facts + baselines. Default is 2 (today + yesterday for late receipts/SMS). Use 7 for backfill.';

-- =============================================================================
-- Versioned API payload view
-- =============================================================================
DROP VIEW IF EXISTS dashboard.v_today;

CREATE OR REPLACE VIEW dashboard.v_today AS
SELECT
    -- API metadata (for caching, debugging)
    1 AS schema_version,
    NOW() AS generated_at,
    life.dubai_today() AS for_date,

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
    f.computed_at AS facts_computed_at,

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
    b.days_with_data_30d,
    b.computed_at AS baselines_computed_at

FROM life.daily_facts f
CROSS JOIN life.baselines b
WHERE f.day = life.dubai_today();

COMMENT ON VIEW dashboard.v_today IS 'Versioned dashboard payload. schema_version for API compatibility, generated_at for caching.';

-- =============================================================================
-- Add schema_version to trends view
-- =============================================================================
DROP VIEW IF EXISTS dashboard.v_trends;

CREATE OR REPLACE VIEW dashboard.v_trends AS
SELECT
    1 AS schema_version,
    NOW() AS generated_at,
    period,
    avg_recovery,
    avg_hrv,
    avg_rhr,
    avg_sleep_minutes,
    avg_strain,
    avg_steps,
    total_spend,
    avg_daily_spend,
    weight_range,
    latest_weight
FROM (
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
    WHERE day >= life.dubai_today() - INTERVAL '7 days'

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
    WHERE day >= life.dubai_today() - INTERVAL '30 days'
) t;

-- =============================================================================
-- Complete API payload function (deterministic, cacheable)
-- =============================================================================
CREATE OR REPLACE FUNCTION dashboard.get_payload(for_date DATE DEFAULT NULL)
RETURNS JSONB AS $$
DECLARE
    target_date DATE := COALESCE(for_date, life.dubai_today());
    payload JSONB;
BEGIN
    SELECT jsonb_build_object(
        'meta', jsonb_build_object(
            'schema_version', 1,
            'generated_at', NOW(),
            'for_date', target_date,
            'timezone', 'Asia/Dubai'
        ),
        'today_facts', (
            SELECT to_jsonb(t.*) - 'schema_version' - 'generated_at' - 'for_date'
            FROM dashboard.v_today t
        ),
        'trends', (
            SELECT jsonb_agg(to_jsonb(t.*) - 'schema_version' - 'generated_at')
            FROM dashboard.v_trends t
        ),
        'feed_status', (
            SELECT jsonb_agg(to_jsonb(f.*))
            FROM ops.feed_status f
        ),
        'recent_events', (
            SELECT COALESCE(jsonb_agg(to_jsonb(e.*)), '[]'::jsonb)
            FROM dashboard.v_recent_events e
        ),
        'stale_feeds', (
            SELECT COALESCE(jsonb_agg(feed), '[]'::jsonb)
            FROM ops.feed_status
            WHERE status IN ('stale', 'critical')
        )
    ) INTO payload;

    RETURN payload;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION dashboard.get_payload IS 'Complete dashboard payload as JSONB. Deterministic for caching. Call with date for historical views.';

COMMIT;
