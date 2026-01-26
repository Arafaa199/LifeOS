-- Rollback migration 085: Remove WHOOP propagation triggers and backfilled data

BEGIN;

-- Drop triggers
DROP TRIGGER IF EXISTS propagate_recovery_to_normalized ON health.whoop_recovery;
DROP TRIGGER IF EXISTS propagate_sleep_to_normalized ON health.whoop_sleep;
DROP TRIGGER IF EXISTS propagate_strain_to_normalized ON health.whoop_strain;

-- Drop functions
DROP FUNCTION IF EXISTS health.propagate_whoop_recovery();
DROP FUNCTION IF EXISTS health.propagate_whoop_sleep();
DROP FUNCTION IF EXISTS health.propagate_whoop_strain();

-- Remove backfilled normalized data (only migration 085 data)
DELETE FROM normalized.daily_recovery WHERE source = 'home_assistant';
DELETE FROM normalized.daily_sleep WHERE source = 'home_assistant';
DELETE FROM normalized.daily_strain WHERE source = 'home_assistant';

-- Remove backfilled raw data (only migration 085 data)
DELETE FROM raw.whoop_cycles WHERE run_id = '00000000-0000-0000-0000-000000000085'::uuid;
DELETE FROM raw.whoop_sleep WHERE run_id = '00000000-0000-0000-0000-000000000085'::uuid;
DELETE FROM raw.whoop_strain WHERE run_id = '00000000-0000-0000-0000-000000000085'::uuid;

COMMIT;
