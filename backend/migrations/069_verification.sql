-- Verification Queries for TASK-HEALTH.2
-- Migration 069: HealthKit Complete Schema

-- =======================
-- 1. Verify Table Structure
-- =======================

-- Check raw.healthkit_samples columns
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'raw' AND table_name = 'healthkit_samples'
ORDER BY ordinal_position;

-- Check raw.healthkit_workouts exists
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'raw' AND table_name = 'healthkit_workouts'
ORDER BY ordinal_position;

-- Check raw.healthkit_sleep exists
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'raw' AND table_name = 'healthkit_sleep'
ORDER BY ordinal_position;

-- =======================
-- 2. Verify Unique Constraints
-- =======================

SELECT
    tc.constraint_name,
    tc.table_name,
    kcu.column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
WHERE tc.table_schema = 'raw'
  AND tc.table_name IN ('healthkit_samples', 'healthkit_workouts', 'healthkit_sleep')
  AND tc.constraint_type = 'UNIQUE'
ORDER BY tc.table_name, tc.constraint_name;

-- =======================
-- 3. Verify View Exists
-- =======================

SELECT table_name, view_definition IS NOT NULL as has_definition
FROM information_schema.views
WHERE table_schema = 'facts' AND table_name = 'v_health_daily';

-- =======================
-- 4. Test Data - Insert Sample Records
-- =======================

-- Insert test sample
INSERT INTO raw.healthkit_samples (sample_id, sample_type, value, unit, start_date, end_date, source_bundle_id, device_name, client_id, source)
VALUES (
  'TEST-SAMPLE-001',
  'HKQuantityTypeIdentifierStepCount',
  1500,
  'count',
  CURRENT_TIMESTAMP - INTERVAL '2 hours',
  CURRENT_TIMESTAMP - INTERVAL '1 hour',
  'com.test.nexus',
  'iPhone',
  gen_random_uuid(),
  'ios_healthkit'
) ON CONFLICT (sample_id, source) DO NOTHING;

-- Insert test workout
INSERT INTO raw.healthkit_workouts (workout_id, type, duration_min, calories, distance_m, start_date, end_date, source_bundle_id, device_name, client_id)
VALUES (
  'TEST-WORKOUT-001',
  'HKWorkoutActivityTypeRunning',
  30,
  250,
  5000,
  CURRENT_TIMESTAMP - INTERVAL '3 hours',
  CURRENT_TIMESTAMP - INTERVAL '2.5 hours',
  'com.test.nexus',
  'Apple Watch',
  gen_random_uuid()
) ON CONFLICT (workout_id, source) DO NOTHING;

-- Insert test sleep
INSERT INTO raw.healthkit_sleep (sleep_id, stage, start_date, end_date, source_bundle_id, device_name, client_id)
VALUES (
  'TEST-SLEEP-001',
  'deep',
  CURRENT_DATE - INTERVAL '8 hours',
  CURRENT_DATE - INTERVAL '6 hours',
  'com.test.nexus',
  'Apple Watch',
  gen_random_uuid()
) ON CONFLICT (sleep_id, source) DO NOTHING;

-- =======================
-- 5. Verify Sample Type Distribution
-- =======================

SELECT sample_type, COUNT(*) as count
FROM raw.healthkit_samples
GROUP BY sample_type
ORDER BY count DESC
LIMIT 20;

-- =======================
-- 6. Verify facts.v_health_daily
-- =======================

SELECT *
FROM facts.v_health_daily
WHERE day >= CURRENT_DATE - 7
ORDER BY day DESC;

-- =======================
-- 7. Verify Idempotency
-- =======================

-- Try inserting duplicate (should be ignored)
INSERT INTO raw.healthkit_samples (sample_id, sample_type, value, unit, start_date, end_date, source_bundle_id, device_name, client_id, source)
VALUES (
  'TEST-SAMPLE-001',
  'HKQuantityTypeIdentifierStepCount',
  1500,
  'count',
  CURRENT_TIMESTAMP - INTERVAL '2 hours',
  CURRENT_TIMESTAMP - INTERVAL '1 hour',
  'com.test.nexus',
  'iPhone',
  gen_random_uuid(),
  'ios_healthkit'
) ON CONFLICT (sample_id, source) DO NOTHING;

-- Should still be 1 row (not duplicated)
SELECT COUNT(*) as count, COUNT(DISTINCT sample_id) as unique_samples
FROM raw.healthkit_samples
WHERE sample_id = 'TEST-SAMPLE-001';

-- =======================
-- 8. Cleanup Test Data
-- =======================

-- Remove test records
DELETE FROM raw.healthkit_samples WHERE sample_id LIKE 'TEST-%';
DELETE FROM raw.healthkit_workouts WHERE workout_id LIKE 'TEST-%';
DELETE FROM raw.healthkit_sleep WHERE sleep_id LIKE 'TEST-%';
