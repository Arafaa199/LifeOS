-- Migration 169 Down: Remove data integrity constraints
--
-- Reverts:
-- - UNIQUE constraint on food_log
-- - raw_id indexes
-- - ON DELETE RESTRICT back to default NO ACTION

BEGIN;

-- =============================================================================
-- 1. Remove UNIQUE constraint on food_log
-- =============================================================================

ALTER TABLE normalized.food_log
DROP CONSTRAINT IF EXISTS uq_food_log_date_meal_logged;

-- =============================================================================
-- 2. Drop raw_id indexes
-- =============================================================================

DROP INDEX IF EXISTS normalized.idx_normalized_recovery_raw_id;
DROP INDEX IF EXISTS normalized.idx_normalized_sleep_raw_id;
DROP INDEX IF EXISTS normalized.idx_normalized_strain_raw_id;
DROP INDEX IF EXISTS normalized.idx_normalized_body_raw_id;
DROP INDEX IF EXISTS normalized.idx_normalized_txn_raw_id;
DROP INDEX IF EXISTS normalized.idx_normalized_food_raw_id;
DROP INDEX IF EXISTS normalized.idx_normalized_water_raw_id;
DROP INDEX IF EXISTS normalized.idx_normalized_mood_raw_id;

-- =============================================================================
-- 3. Revert FK constraints to default NO ACTION
-- =============================================================================

-- daily_recovery
ALTER TABLE normalized.daily_recovery
DROP CONSTRAINT IF EXISTS daily_recovery_raw_id_fkey;

ALTER TABLE normalized.daily_recovery
ADD CONSTRAINT daily_recovery_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.whoop_cycles(id);

-- daily_sleep
ALTER TABLE normalized.daily_sleep
DROP CONSTRAINT IF EXISTS daily_sleep_raw_id_fkey;

ALTER TABLE normalized.daily_sleep
ADD CONSTRAINT daily_sleep_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.whoop_sleep(id);

-- daily_strain
ALTER TABLE normalized.daily_strain
DROP CONSTRAINT IF EXISTS daily_strain_raw_id_fkey;

ALTER TABLE normalized.daily_strain
ADD CONSTRAINT daily_strain_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.whoop_strain(id);

-- body_metrics
ALTER TABLE normalized.body_metrics
DROP CONSTRAINT IF EXISTS body_metrics_raw_id_fkey;

ALTER TABLE normalized.body_metrics
ADD CONSTRAINT body_metrics_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.healthkit_samples(id);

-- transactions
ALTER TABLE normalized.transactions
DROP CONSTRAINT IF EXISTS transactions_raw_id_fkey;

ALTER TABLE normalized.transactions
ADD CONSTRAINT transactions_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.bank_sms(id);

-- food_log
ALTER TABLE normalized.food_log
DROP CONSTRAINT IF EXISTS food_log_raw_id_fkey;

ALTER TABLE normalized.food_log
ADD CONSTRAINT food_log_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.manual_entries(id);

-- water_log
ALTER TABLE normalized.water_log
DROP CONSTRAINT IF EXISTS water_log_raw_id_fkey;

ALTER TABLE normalized.water_log
ADD CONSTRAINT water_log_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.manual_entries(id);

-- mood_log
ALTER TABLE normalized.mood_log
DROP CONSTRAINT IF EXISTS mood_log_raw_id_fkey;

ALTER TABLE normalized.mood_log
ADD CONSTRAINT mood_log_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.manual_entries(id);

COMMIT;
