-- Migration 069: Complete HealthKit Backend Schema
-- Task: TASK-HEALTH.2
-- Purpose: Prepare backend for iOS HealthKit batch ingestion

-- =======================
-- 1. Update raw.healthkit_samples
-- =======================

-- Add missing columns for iOS compatibility
ALTER TABLE raw.healthkit_samples
  ADD COLUMN IF NOT EXISTS sample_id VARCHAR(255),
  ADD COLUMN IF NOT EXISTS source_bundle_id VARCHAR(100),
  ADD COLUMN IF NOT EXISTS client_id UUID;

-- Set default for run_id (required for inserts)
ALTER TABLE raw.healthkit_samples
  ALTER COLUMN run_id SET DEFAULT gen_random_uuid();

-- Create unique constraint on (sample_id, source) for idempotency
-- Use ALTER TABLE ADD CONSTRAINT instead of CREATE UNIQUE INDEX for ON CONFLICT support
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_schema = 'raw'
    AND table_name = 'healthkit_samples'
    AND constraint_name = 'uq_healthkit_samples_sample_id_source_v2'
  ) THEN
    ALTER TABLE raw.healthkit_samples
      ADD CONSTRAINT uq_healthkit_samples_sample_id_source_v2 UNIQUE (sample_id, source);
  END IF;
END $$;

-- Create index on client_id for iOS app queries
CREATE INDEX IF NOT EXISTS idx_healthkit_samples_client_id
  ON raw.healthkit_samples(client_id)
  WHERE client_id IS NOT NULL;

COMMENT ON COLUMN raw.healthkit_samples.sample_id IS 'iOS HealthKit UUID for idempotency';
COMMENT ON COLUMN raw.healthkit_samples.source_bundle_id IS 'iOS app bundle identifier';
COMMENT ON COLUMN raw.healthkit_samples.client_id IS 'Client-generated UUID for request tracking';

-- =======================
-- 2. Create raw.healthkit_workouts
-- =======================

CREATE TABLE IF NOT EXISTS raw.healthkit_workouts (
    id BIGSERIAL PRIMARY KEY,
    workout_id VARCHAR(255) NOT NULL,
    type VARCHAR(100) NOT NULL,
    duration_min NUMERIC(8,2),
    calories NUMERIC(8,2),
    distance_m NUMERIC(10,2),
    start_date TIMESTAMPTZ NOT NULL,
    end_date TIMESTAMPTZ NOT NULL,
    source VARCHAR(50) NOT NULL DEFAULT 'ios_healthkit',
    device_name VARCHAR(100),
    source_bundle_id VARCHAR(100),
    metadata JSONB,
    client_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Unique constraint for idempotency
CREATE UNIQUE INDEX uq_healthkit_workouts_workout_id_source
  ON raw.healthkit_workouts(workout_id, source);

-- Indexes
CREATE INDEX idx_healthkit_workouts_start_date
  ON raw.healthkit_workouts(start_date DESC);

CREATE INDEX idx_healthkit_workouts_type
  ON raw.healthkit_workouts(type, start_date DESC);

CREATE INDEX idx_healthkit_workouts_client_id
  ON raw.healthkit_workouts(client_id)
  WHERE client_id IS NOT NULL;

-- Immutability trigger
CREATE TRIGGER prevent_update_healthkit_workouts
  BEFORE UPDATE OR DELETE ON raw.healthkit_workouts
  FOR EACH ROW EXECUTE FUNCTION raw.prevent_modification();

COMMENT ON TABLE raw.healthkit_workouts IS 'Raw HealthKit workout data from iOS';

-- =======================
-- 3. Create raw.healthkit_sleep
-- =======================

CREATE TABLE IF NOT EXISTS raw.healthkit_sleep (
    id BIGSERIAL PRIMARY KEY,
    sleep_id VARCHAR(255) NOT NULL,
    stage VARCHAR(50) NOT NULL, -- inBed, asleep, awake, core, deep, rem
    start_date TIMESTAMPTZ NOT NULL,
    end_date TIMESTAMPTZ NOT NULL,
    source VARCHAR(50) NOT NULL DEFAULT 'ios_healthkit',
    device_name VARCHAR(100),
    source_bundle_id VARCHAR(100),
    metadata JSONB,
    client_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Unique constraint for idempotency
CREATE UNIQUE INDEX uq_healthkit_sleep_sleep_id_source
  ON raw.healthkit_sleep(sleep_id, source);

-- Indexes
CREATE INDEX idx_healthkit_sleep_start_date
  ON raw.healthkit_sleep(start_date DESC);

CREATE INDEX idx_healthkit_sleep_stage
  ON raw.healthkit_sleep(stage, start_date DESC);

CREATE INDEX idx_healthkit_sleep_client_id
  ON raw.healthkit_sleep(client_id)
  WHERE client_id IS NOT NULL;

-- Immutability trigger
CREATE TRIGGER prevent_update_healthkit_sleep
  BEFORE UPDATE OR DELETE ON raw.healthkit_sleep
  FOR EACH ROW EXECUTE FUNCTION raw.prevent_modification();

COMMENT ON TABLE raw.healthkit_sleep IS 'Raw HealthKit sleep analysis data from iOS';

-- =======================
-- 4. Create facts.v_health_daily
-- =======================

CREATE OR REPLACE VIEW facts.v_health_daily AS
WITH samples_daily AS (
  SELECT
    (start_date AT TIME ZONE 'Asia/Dubai')::DATE AS day,
    sample_type,
    SUM(value) FILTER (WHERE sample_type IN ('HKQuantityTypeIdentifierStepCount', 'HKQuantityTypeIdentifierActiveEnergyBurned', 'HKQuantityTypeIdentifierBasalEnergyBurned')) AS total_value,
    AVG(value) FILTER (WHERE sample_type = 'HKQuantityTypeIdentifierHeartRate') AS avg_heart_rate,
    MIN(value) FILTER (WHERE sample_type = 'HKQuantityTypeIdentifierHeartRate') AS min_heart_rate,
    MAX(value) FILTER (WHERE sample_type = 'HKQuantityTypeIdentifierHeartRate') AS max_heart_rate
  FROM raw.healthkit_samples
  GROUP BY day, sample_type
),
workouts_daily AS (
  SELECT
    (start_date AT TIME ZONE 'Asia/Dubai')::DATE AS day,
    COUNT(*) AS workout_count,
    SUM(duration_min) AS total_duration_min,
    SUM(calories) AS total_calories,
    SUM(distance_m) AS total_distance_m
  FROM raw.healthkit_workouts
  GROUP BY day
),
sleep_daily AS (
  SELECT
    (start_date AT TIME ZONE 'Asia/Dubai')::DATE AS day,
    stage,
    SUM(EXTRACT(EPOCH FROM (end_date - start_date)) / 3600) AS hours
  FROM raw.healthkit_sleep
  GROUP BY day, stage
)
SELECT
  COALESCE(s.day, w.day, sl.day) AS day,
  MAX(s.total_value) FILTER (WHERE s.sample_type = 'HKQuantityTypeIdentifierStepCount') AS steps,
  MAX(s.total_value) FILTER (WHERE s.sample_type = 'HKQuantityTypeIdentifierActiveEnergyBurned') AS active_calories,
  MAX(s.total_value) FILTER (WHERE s.sample_type = 'HKQuantityTypeIdentifierBasalEnergyBurned') AS resting_calories,
  MAX(s.avg_heart_rate) AS avg_heart_rate,
  MAX(s.min_heart_rate) AS min_heart_rate,
  MAX(s.max_heart_rate) AS max_heart_rate,
  w.workout_count,
  w.total_duration_min AS workout_duration_min,
  w.total_calories AS workout_calories,
  w.total_distance_m AS workout_distance_m,
  MAX(sl.hours) FILTER (WHERE sl.stage = 'asleep') AS sleep_hours_asleep,
  MAX(sl.hours) FILTER (WHERE sl.stage = 'core') AS sleep_hours_core,
  MAX(sl.hours) FILTER (WHERE sl.stage = 'deep') AS sleep_hours_deep,
  MAX(sl.hours) FILTER (WHERE sl.stage = 'rem') AS sleep_hours_rem,
  MAX(sl.hours) FILTER (WHERE sl.stage = 'inBed') AS sleep_hours_in_bed
FROM samples_daily s
FULL OUTER JOIN workouts_daily w ON s.day = w.day
FULL OUTER JOIN sleep_daily sl ON COALESCE(s.day, w.day) = sl.day
GROUP BY COALESCE(s.day, w.day, sl.day), w.workout_count, w.total_duration_min, w.total_calories, w.total_distance_m
ORDER BY day DESC;

COMMENT ON VIEW facts.v_health_daily IS 'Daily aggregated HealthKit metrics from iOS';
