-- Migration 169: Data Integrity Constraints
--
-- This migration adds:
-- (a) UNIQUE constraint on normalized.food_log (date, meal_time, logged_at) with dedup
-- (b) Indexes on all raw_id FK columns in normalized.* tables
-- (c) ON DELETE RESTRICT on all raw_id REFERENCES in normalized schema
--
-- Wrapped in transaction for atomicity.

BEGIN;

-- =============================================================================
-- 1. Deduplicate food_log before adding UNIQUE constraint
--
-- Strategy: Keep the row with the highest id (latest inserted) per key
-- =============================================================================

-- First, identify and delete duplicates (keep highest id per key)
DELETE FROM normalized.food_log
WHERE id NOT IN (
    SELECT MAX(id)
    FROM normalized.food_log
    GROUP BY date, meal_time, logged_at
);

-- Report how many duplicates were removed (for logging)
DO $$
DECLARE
    deleted_count INT;
BEGIN
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    IF deleted_count > 0 THEN
        RAISE NOTICE 'Removed % duplicate food_log rows', deleted_count;
    END IF;
END $$;

-- Now add the UNIQUE constraint
ALTER TABLE normalized.food_log
ADD CONSTRAINT uq_food_log_date_meal_logged
UNIQUE (date, meal_time, logged_at);

COMMENT ON CONSTRAINT uq_food_log_date_meal_logged ON normalized.food_log IS
'Prevents duplicate food log entries for the same date, meal time, and timestamp';

-- =============================================================================
-- 2. Create indexes on raw_id FK columns for faster joins/lookups
--
-- These improve performance when querying by source or joining to raw tables
-- =============================================================================

-- daily_recovery
CREATE INDEX IF NOT EXISTS idx_normalized_recovery_raw_id
    ON normalized.daily_recovery(raw_id)
    WHERE raw_id IS NOT NULL;

-- daily_sleep
CREATE INDEX IF NOT EXISTS idx_normalized_sleep_raw_id
    ON normalized.daily_sleep(raw_id)
    WHERE raw_id IS NOT NULL;

-- daily_strain
CREATE INDEX IF NOT EXISTS idx_normalized_strain_raw_id
    ON normalized.daily_strain(raw_id)
    WHERE raw_id IS NOT NULL;

-- body_metrics
CREATE INDEX IF NOT EXISTS idx_normalized_body_raw_id
    ON normalized.body_metrics(raw_id)
    WHERE raw_id IS NOT NULL;

-- transactions
CREATE INDEX IF NOT EXISTS idx_normalized_txn_raw_id
    ON normalized.transactions(raw_id)
    WHERE raw_id IS NOT NULL;

-- food_log
CREATE INDEX IF NOT EXISTS idx_normalized_food_raw_id
    ON normalized.food_log(raw_id)
    WHERE raw_id IS NOT NULL;

-- water_log
CREATE INDEX IF NOT EXISTS idx_normalized_water_raw_id
    ON normalized.water_log(raw_id)
    WHERE raw_id IS NOT NULL;

-- mood_log
CREATE INDEX IF NOT EXISTS idx_normalized_mood_raw_id
    ON normalized.mood_log(raw_id)
    WHERE raw_id IS NOT NULL;

-- =============================================================================
-- 3. Replace FK constraints with ON DELETE RESTRICT
--
-- This prevents accidental deletion of raw data that has normalized references.
-- The default NO ACTION is similar but RESTRICT is stricter (can't defer check).
--
-- Strategy: Drop old constraint, add new with RESTRICT.
-- =============================================================================

-- daily_recovery: raw.whoop_cycles
ALTER TABLE normalized.daily_recovery
DROP CONSTRAINT IF EXISTS daily_recovery_raw_id_fkey;

ALTER TABLE normalized.daily_recovery
ADD CONSTRAINT daily_recovery_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.whoop_cycles(id) ON DELETE RESTRICT;

-- daily_sleep: raw.whoop_sleep
ALTER TABLE normalized.daily_sleep
DROP CONSTRAINT IF EXISTS daily_sleep_raw_id_fkey;

ALTER TABLE normalized.daily_sleep
ADD CONSTRAINT daily_sleep_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.whoop_sleep(id) ON DELETE RESTRICT;

-- daily_strain: raw.whoop_strain
ALTER TABLE normalized.daily_strain
DROP CONSTRAINT IF EXISTS daily_strain_raw_id_fkey;

ALTER TABLE normalized.daily_strain
ADD CONSTRAINT daily_strain_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.whoop_strain(id) ON DELETE RESTRICT;

-- body_metrics: raw.healthkit_samples
ALTER TABLE normalized.body_metrics
DROP CONSTRAINT IF EXISTS body_metrics_raw_id_fkey;

ALTER TABLE normalized.body_metrics
ADD CONSTRAINT body_metrics_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.healthkit_samples(id) ON DELETE RESTRICT;

-- transactions: raw.bank_sms
ALTER TABLE normalized.transactions
DROP CONSTRAINT IF EXISTS transactions_raw_id_fkey;

ALTER TABLE normalized.transactions
ADD CONSTRAINT transactions_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.bank_sms(id) ON DELETE RESTRICT;

-- food_log: raw.manual_entries
ALTER TABLE normalized.food_log
DROP CONSTRAINT IF EXISTS food_log_raw_id_fkey;

ALTER TABLE normalized.food_log
ADD CONSTRAINT food_log_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.manual_entries(id) ON DELETE RESTRICT;

-- water_log: raw.manual_entries
ALTER TABLE normalized.water_log
DROP CONSTRAINT IF EXISTS water_log_raw_id_fkey;

ALTER TABLE normalized.water_log
ADD CONSTRAINT water_log_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.manual_entries(id) ON DELETE RESTRICT;

-- mood_log: raw.manual_entries
ALTER TABLE normalized.mood_log
DROP CONSTRAINT IF EXISTS mood_log_raw_id_fkey;

ALTER TABLE normalized.mood_log
ADD CONSTRAINT mood_log_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.manual_entries(id) ON DELETE RESTRICT;

-- =============================================================================
-- 4. Verification query (commented out for automated execution)
-- =============================================================================

-- SELECT
--     tc.table_name,
--     tc.constraint_name,
--     rc.delete_rule
-- FROM information_schema.table_constraints tc
-- JOIN information_schema.referential_constraints rc
--     ON tc.constraint_name = rc.constraint_name
-- WHERE tc.table_schema = 'normalized'
--   AND tc.constraint_type = 'FOREIGN KEY'
-- ORDER BY tc.table_name;

COMMIT;
