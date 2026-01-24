-- Rollback: 008_update_for_quarantine
-- Purpose: Restore functions and views to NOT exclude quarantined transactions
-- Date: 2026-01-21
--
-- Note: This restores the original functions without quarantine filtering.
-- The quarantine columns and data remain - only the filtering is removed.

BEGIN;

-- ============================================================================
-- 1. Restore original life.refresh_daily_facts() without quarantine filter
-- ============================================================================

CREATE OR REPLACE FUNCTION life.refresh_daily_facts(target_day date DEFAULT NULL::date, triggered_by character varying DEFAULT 'manual'::character varying)
 RETURNS TABLE(status text, rows_affected integer, duration_ms integer)
 LANGUAGE plpgsql
AS $function$
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
$function$;

-- ============================================================================
-- 2. Restore original dashboard.v_recent_events without quarantine filter
-- ============================================================================

CREATE OR REPLACE VIEW dashboard.v_recent_events AS
SELECT
    'transaction'::text AS event_type,
    date AS event_date,
    date::timestamp without time zone AS event_time,
    jsonb_build_object(
        'merchant', merchant_name,
        'amount', amount,
        'category', category
    ) AS payload
FROM finance.transactions t
WHERE date >= (CURRENT_DATE - '7 days'::interval)
ORDER BY date DESC
LIMIT 10;

COMMIT;
