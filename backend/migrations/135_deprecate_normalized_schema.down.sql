-- Migration 135 DOWN: Restore normalized schema
-- Recreates the normalized schema and tables, restores triggers to write to both raw + normalized.
-- NOTE: Data in normalized tables will need to be re-backfilled from raw after rollback.

BEGIN;

-- 1. Recreate normalized schema
CREATE SCHEMA IF NOT EXISTS normalized;

-- 2. Recreate normalized tables

CREATE TABLE normalized.daily_recovery (
    date DATE PRIMARY KEY,
    recovery_score INT,
    hrv NUMERIC(6,2),
    rhr INT,
    spo2 DECIMAL(4,1),
    skin_temp_c DECIMAL(4,2),
    raw_id BIGINT REFERENCES raw.whoop_cycles(id),
    source VARCHAR(50) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE normalized.daily_sleep (
    date DATE PRIMARY KEY,
    sleep_start TIMESTAMPTZ,
    sleep_end TIMESTAMPTZ,
    total_sleep_min INT,
    time_in_bed_min INT,
    light_sleep_min INT,
    deep_sleep_min INT,
    rem_sleep_min INT,
    awake_min INT,
    sleep_efficiency DECIMAL(5,2),
    sleep_performance INT,
    respiratory_rate DECIMAL(4,1),
    raw_id BIGINT REFERENCES raw.whoop_sleep(id),
    source VARCHAR(50) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE normalized.daily_strain (
    date DATE PRIMARY KEY,
    day_strain DECIMAL(4,1),
    calories_burned INT,
    calories_active INT,
    workout_count INT,
    average_hr INT,
    max_hr INT,
    raw_id BIGINT REFERENCES raw.whoop_strain(id),
    source VARCHAR(50) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE normalized.body_metrics (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    metric_type VARCHAR(50) NOT NULL,
    value DECIMAL(8,2) NOT NULL,
    unit VARCHAR(20),
    source VARCHAR(50) NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(date, metric_type, source)
);

CREATE TABLE normalized.transactions (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'AED',
    merchant_name VARCHAR(255),
    category VARCHAR(100),
    source VARCHAR(50) NOT NULL,
    raw_id BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE normalized.food_log (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    meal_time TIMESTAMPTZ,
    description TEXT,
    calories INT,
    protein_g DECIMAL(6,1),
    carbs_g DECIMAL(6,1),
    fat_g DECIMAL(6,1),
    source VARCHAR(50) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE normalized.water_log (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    amount_ml INT NOT NULL,
    source VARCHAR(50) NOT NULL DEFAULT 'manual',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE normalized.mood_log (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    mood_score INT,
    energy_level INT,
    notes TEXT,
    source VARCHAR(50) NOT NULL DEFAULT 'manual',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Restore v_daily_finance in normalized schema
CREATE OR REPLACE VIEW normalized.v_daily_finance AS
WITH daily_category AS (
    SELECT
        finance.to_business_date(transaction_at) AS date,
        COALESCE(category, 'Uncategorized'::varchar) AS category,
        SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END) AS cat_spend,
        SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) AS cat_income,
        COUNT(*) AS cat_count
    FROM finance.transactions
    WHERE is_quarantined IS NOT TRUE
      AND pairing_role IS DISTINCT FROM 'fx_metadata'
      AND category NOT IN ('Transfer', 'CC Payment', 'BNPL Repayment', 'Credit Card Payment')
    GROUP BY finance.to_business_date(transaction_at), COALESCE(category, 'Uncategorized'::varchar)
)
SELECT
    date,
    COALESCE(SUM(cat_spend), 0) AS spend_total,
    COALESCE(SUM(cat_income), 0) AS income_total,
    SUM(cat_count)::integer AS transaction_count,
    COALESCE(SUM(CASE WHEN category = 'Groceries' THEN cat_spend END), 0) AS spend_groceries,
    COALESCE(SUM(CASE WHEN category IN ('Dining', 'Restaurants', 'Food Delivery') THEN cat_spend END), 0) AS spend_restaurants,
    COALESCE(SUM(CASE WHEN category = 'Transport' THEN cat_spend END), 0) AS spend_transport,
    jsonb_object_agg(category, cat_spend) FILTER (WHERE cat_spend > 0) AS spending_by_category
FROM daily_category
GROUP BY date;

-- 4. Drop finance.v_daily_finance (added by up migration)
DROP VIEW IF EXISTS finance.v_daily_finance;

-- 5. Backfill normalized WHOOP tables from raw
INSERT INTO normalized.daily_recovery (date, recovery_score, hrv, rhr, spo2, raw_id, source, updated_at)
SELECT date, recovery_score, hrv, rhr, spo2, id, source, ingested_at
FROM raw.whoop_cycles
ON CONFLICT (date) DO NOTHING;

INSERT INTO normalized.daily_sleep (date, sleep_start, sleep_end, total_sleep_min, time_in_bed_min, light_sleep_min, deep_sleep_min, rem_sleep_min, awake_min, sleep_efficiency, sleep_performance, respiratory_rate, raw_id, source, updated_at)
SELECT date, sleep_start, sleep_end,
    (COALESCE(time_in_bed_ms, 0) - COALESCE(awake_ms, 0))::integer / 60000,
    time_in_bed_ms::integer / 60000,
    light_sleep_ms::integer / 60000,
    deep_sleep_ms::integer / 60000,
    rem_sleep_ms::integer / 60000,
    awake_ms::integer / 60000,
    sleep_efficiency, sleep_performance, respiratory_rate,
    id, source, ingested_at
FROM raw.whoop_sleep
ON CONFLICT (date) DO NOTHING;

INSERT INTO normalized.daily_strain (date, day_strain, calories_burned, calories_active, workout_count, average_hr, max_hr, raw_id, source, updated_at)
SELECT date, day_strain, (kilojoules / 4.184)::integer, calories_active, workout_count, average_hr, max_hr, id, source, ingested_at
FROM raw.whoop_strain
ON CONFLICT (date) DO NOTHING;

-- 6. Restore triggers to write to both raw + normalized (from migration 126)
-- Recovery
CREATE OR REPLACE FUNCTION health.propagate_whoop_recovery() RETURNS TRIGGER AS $$
DECLARE
    v_raw_id bigint;
BEGIN
    INSERT INTO raw.whoop_cycles (cycle_id, date, recovery_score, hrv, rhr, spo2, skin_temp, raw_json, source, ingested_at, run_id)
    VALUES (
        NEW.id, NEW.date, NEW.recovery_score, NEW.hrv_rmssd, NEW.rhr, NEW.spo2, NEW.skin_temp,
        COALESCE(NEW.raw_data, jsonb_build_object(
            'recovery_score', NEW.recovery_score, 'hrv_rmssd', NEW.hrv_rmssd,
            'rhr', NEW.rhr, 'spo2', NEW.spo2, 'skin_temp', NEW.skin_temp,
            'sleep_performance', NEW.sleep_performance, 'propagated_at', now()
        )),
        'whoop_api', NOW(), gen_random_uuid()
    )
    ON CONFLICT (date) DO UPDATE SET
        cycle_id = EXCLUDED.cycle_id, recovery_score = EXCLUDED.recovery_score,
        hrv = EXCLUDED.hrv, rhr = EXCLUDED.rhr, spo2 = EXCLUDED.spo2,
        skin_temp = EXCLUDED.skin_temp, raw_json = EXCLUDED.raw_json, ingested_at = NOW()
    RETURNING id INTO v_raw_id;

    INSERT INTO normalized.daily_recovery (date, recovery_score, hrv, rhr, spo2, skin_temp_c, raw_id, source, updated_at)
    VALUES (NEW.date, NEW.recovery_score, NEW.hrv_rmssd, NEW.rhr, NEW.spo2, NEW.skin_temp, v_raw_id, 'whoop_api', NOW())
    ON CONFLICT (date) DO UPDATE SET
        recovery_score = EXCLUDED.recovery_score, hrv = EXCLUDED.hrv, rhr = EXCLUDED.rhr,
        spo2 = EXCLUDED.spo2, skin_temp_c = EXCLUDED.skin_temp_c, raw_id = EXCLUDED.raw_id,
        source = EXCLUDED.source, updated_at = NOW();

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
    VALUES ('propagate_whoop_recovery', TG_TABLE_NAME, SQLERRM, SQLSTATE);
    RAISE WARNING 'propagate_whoop_recovery failed for date %: % [%]', NEW.date, SQLERRM, SQLSTATE;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Sleep
CREATE OR REPLACE FUNCTION health.propagate_whoop_sleep() RETURNS TRIGGER AS $$
DECLARE
    v_raw_id bigint;
BEGIN
    INSERT INTO raw.whoop_sleep (sleep_id, date, sleep_start, sleep_end, time_in_bed_ms, light_sleep_ms, deep_sleep_ms, rem_sleep_ms, awake_ms, sleep_efficiency, sleep_performance, respiratory_rate, raw_json, source, ingested_at, run_id)
    VALUES (
        NEW.id, NEW.date, NEW.sleep_start, NEW.sleep_end,
        NEW.time_in_bed_min * 60000, NEW.light_sleep_min * 60000,
        NEW.deep_sleep_min * 60000, NEW.rem_sleep_min * 60000,
        NEW.awake_min * 60000, NEW.sleep_efficiency, NEW.sleep_performance, NEW.respiratory_rate,
        COALESCE(NEW.raw_data, jsonb_build_object(
            'time_in_bed_min', NEW.time_in_bed_min, 'deep_sleep_min', NEW.deep_sleep_min,
            'rem_sleep_min', NEW.rem_sleep_min, 'light_sleep_min', NEW.light_sleep_min,
            'propagated_at', now()
        )),
        'whoop_api', NOW(), gen_random_uuid()
    )
    ON CONFLICT (date) DO UPDATE SET
        sleep_id = EXCLUDED.sleep_id, sleep_start = EXCLUDED.sleep_start, sleep_end = EXCLUDED.sleep_end,
        time_in_bed_ms = EXCLUDED.time_in_bed_ms, light_sleep_ms = EXCLUDED.light_sleep_ms,
        deep_sleep_ms = EXCLUDED.deep_sleep_ms, rem_sleep_ms = EXCLUDED.rem_sleep_ms,
        awake_ms = EXCLUDED.awake_ms, sleep_efficiency = EXCLUDED.sleep_efficiency,
        sleep_performance = EXCLUDED.sleep_performance, respiratory_rate = EXCLUDED.respiratory_rate,
        raw_json = EXCLUDED.raw_json, ingested_at = NOW()
    RETURNING id INTO v_raw_id;

    INSERT INTO normalized.daily_sleep (date, sleep_start, sleep_end, total_sleep_min, time_in_bed_min, light_sleep_min, deep_sleep_min, rem_sleep_min, awake_min, sleep_efficiency, sleep_performance, respiratory_rate, raw_id, source, updated_at)
    VALUES (
        NEW.date, NEW.sleep_start, NEW.sleep_end,
        COALESCE(NEW.time_in_bed_min, 0) - COALESCE(NEW.awake_min, 0),
        NEW.time_in_bed_min, NEW.light_sleep_min, NEW.deep_sleep_min,
        NEW.rem_sleep_min, NEW.awake_min, NEW.sleep_efficiency,
        NEW.sleep_performance, NEW.respiratory_rate, v_raw_id, 'whoop_api', NOW()
    )
    ON CONFLICT (date) DO UPDATE SET
        sleep_start = EXCLUDED.sleep_start, sleep_end = EXCLUDED.sleep_end,
        total_sleep_min = EXCLUDED.total_sleep_min, time_in_bed_min = EXCLUDED.time_in_bed_min,
        light_sleep_min = EXCLUDED.light_sleep_min, deep_sleep_min = EXCLUDED.deep_sleep_min,
        rem_sleep_min = EXCLUDED.rem_sleep_min, awake_min = EXCLUDED.awake_min,
        sleep_efficiency = EXCLUDED.sleep_efficiency, sleep_performance = EXCLUDED.sleep_performance,
        respiratory_rate = EXCLUDED.respiratory_rate, raw_id = EXCLUDED.raw_id,
        source = EXCLUDED.source, updated_at = NOW();

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
    VALUES ('propagate_whoop_sleep', TG_TABLE_NAME, SQLERRM, SQLSTATE);
    RAISE WARNING 'propagate_whoop_sleep failed for date %: % [%]', NEW.date, SQLERRM, SQLSTATE;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Strain
CREATE OR REPLACE FUNCTION health.propagate_whoop_strain() RETURNS TRIGGER AS $$
DECLARE
    v_raw_id bigint;
BEGIN
    INSERT INTO raw.whoop_strain (strain_id, date, day_strain, workout_count, kilojoules, average_hr, max_hr, calories_active, raw_json, source, ingested_at, run_id)
    VALUES (
        NEW.id, NEW.date, NEW.day_strain, 0,
        NEW.calories_total * 4.184, NEW.avg_hr, NEW.max_hr, NEW.calories_active,
        COALESCE(NEW.raw_data, jsonb_build_object(
            'day_strain', NEW.day_strain, 'calories_total', NEW.calories_total,
            'calories_active', NEW.calories_active, 'propagated_at', now()
        )),
        'whoop_api', NOW(), gen_random_uuid()
    )
    ON CONFLICT (date) DO UPDATE SET
        strain_id = EXCLUDED.strain_id, day_strain = EXCLUDED.day_strain,
        kilojoules = EXCLUDED.kilojoules, average_hr = EXCLUDED.average_hr,
        max_hr = EXCLUDED.max_hr, calories_active = EXCLUDED.calories_active,
        raw_json = EXCLUDED.raw_json, ingested_at = NOW()
    RETURNING id INTO v_raw_id;

    INSERT INTO normalized.daily_strain (date, day_strain, calories_burned, calories_active, workout_count, average_hr, max_hr, raw_id, source, updated_at)
    VALUES (NEW.date, NEW.day_strain, NEW.calories_total, NEW.calories_active, 0, NEW.avg_hr, NEW.max_hr, v_raw_id, 'whoop_api', NOW())
    ON CONFLICT (date) DO UPDATE SET
        day_strain = EXCLUDED.day_strain, calories_burned = EXCLUDED.calories_burned,
        calories_active = EXCLUDED.calories_active, average_hr = EXCLUDED.average_hr,
        max_hr = EXCLUDED.max_hr, raw_id = EXCLUDED.raw_id,
        source = EXCLUDED.source, updated_at = NOW();

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
    VALUES ('propagate_whoop_strain', TG_TABLE_NAME, SQLERRM, SQLSTATE);
    RAISE WARNING 'propagate_whoop_strain failed for date %: % [%]', NEW.date, SQLERRM, SQLSTATE;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 7. Restore refresh_daily_facts to read from normalized (migration 120 version)
-- NOTE: Run migration 120 up to fully restore. This down migration only restores the schema structure.

COMMIT;
