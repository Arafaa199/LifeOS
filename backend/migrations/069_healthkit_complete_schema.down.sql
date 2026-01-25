-- Migration 069 Rollback: Remove HealthKit Complete Schema

-- Drop view
DROP VIEW IF EXISTS facts.v_health_daily;

-- Drop tables
DROP TABLE IF EXISTS raw.healthkit_sleep CASCADE;
DROP TABLE IF EXISTS raw.healthkit_workouts CASCADE;

-- Remove added columns from healthkit_samples
ALTER TABLE raw.healthkit_samples
  DROP COLUMN IF EXISTS sample_id,
  DROP COLUMN IF EXISTS source_bundle_id,
  DROP COLUMN IF EXISTS client_id;

-- Drop indexes (they'll be dropped with columns, but explicit for clarity)
DROP INDEX IF EXISTS raw.uq_healthkit_samples_sample_id_source;
DROP INDEX IF EXISTS raw.idx_healthkit_samples_client_id;
