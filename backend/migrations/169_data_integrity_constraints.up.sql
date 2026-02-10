-- Migration 169: Data Integrity Constraints
--
-- Fixes three data integrity gaps identified in the audit:
--   (a) UNIQUE constraint on normalized.food_log — prevents duplicate entries
--   (b) Indexes on all raw_id FK columns — prevents full table scans
--   (c) ON DELETE RESTRICT on all raw_id FKs — enforces referential integrity
--
-- NULL handling: meal_time and logged_at can be NULL. PostgreSQL UNIQUE treats
-- each NULL as distinct, so we use COALESCE in a unique index instead of a
-- UNIQUE constraint to properly deduplicate rows with NULLs.

BEGIN;

-- =============================================================================
-- 1. Deduplicate food_log BEFORE adding constraint
--
-- Uses ROW_NUMBER() window function to handle NULLs correctly.
-- COALESCE ensures NULL meal_time and NULL logged_at are treated as equal.
-- Keeps the row with the highest id (most recently inserted) per logical key.
-- =============================================================================

-- Count before (for logging)
DO $$
DECLARE
    total_before INT;
    total_after INT;
    dupes_removed INT;
BEGIN
    SELECT count(*) INTO total_before FROM normalized.food_log;

    -- Delete duplicates: keep highest id per (date, meal_time, logged_at)
    -- NULLs are coalesced to sentinel values for grouping purposes
    DELETE FROM normalized.food_log
    WHERE id IN (
        SELECT id FROM (
            SELECT id,
                   ROW_NUMBER() OVER (
                       PARTITION BY date,
                                    COALESCE(meal_time, '__null__'),
                                    COALESCE(logged_at::text, '__null__')
                       ORDER BY id DESC
                   ) AS rn
            FROM normalized.food_log
        ) ranked
        WHERE rn > 1
    );

    SELECT count(*) INTO total_after FROM normalized.food_log;
    dupes_removed := total_before - total_after;

    IF dupes_removed > 0 THEN
        RAISE NOTICE 'food_log dedup: removed % duplicates (% → % rows)',
            dupes_removed, total_before, total_after;
    ELSE
        RAISE NOTICE 'food_log dedup: no duplicates found (% rows)', total_before;
    END IF;
END $$;

-- Create a UNIQUE INDEX (not constraint) with COALESCE for NULL-safe dedup
-- This prevents future duplicates even when meal_time or logged_at is NULL
CREATE UNIQUE INDEX IF NOT EXISTS uix_food_log_date_meal_logged
    ON normalized.food_log (
        date,
        COALESCE(meal_time, '__null__'),
        COALESCE(logged_at::text, '__null__')
    );

COMMENT ON INDEX normalized.uix_food_log_date_meal_logged IS
'NULL-safe unique index preventing duplicate food_log entries.
Uses COALESCE so NULLs in meal_time/logged_at are treated as equal.
Migration 169.';

-- =============================================================================
-- 2. Create indexes on raw_id FK columns for faster joins/lookups
--
-- Partial indexes (WHERE raw_id IS NOT NULL) keep index small and avoid
-- indexing rows that don't have a raw source reference.
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_normalized_recovery_raw_id
    ON normalized.daily_recovery(raw_id)
    WHERE raw_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_normalized_sleep_raw_id
    ON normalized.daily_sleep(raw_id)
    WHERE raw_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_normalized_strain_raw_id
    ON normalized.daily_strain(raw_id)
    WHERE raw_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_normalized_body_raw_id
    ON normalized.body_metrics(raw_id)
    WHERE raw_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_normalized_txn_raw_id
    ON normalized.transactions(raw_id)
    WHERE raw_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_normalized_food_raw_id
    ON normalized.food_log(raw_id)
    WHERE raw_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_normalized_water_raw_id
    ON normalized.water_log(raw_id)
    WHERE raw_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_normalized_mood_raw_id
    ON normalized.mood_log(raw_id)
    WHERE raw_id IS NOT NULL;

-- =============================================================================
-- 3. Replace FK constraints with ON DELETE RESTRICT
--
-- RESTRICT is stricter than default NO ACTION: it cannot be deferred and
-- prevents deletion even within a transaction. Combined with the raw layer's
-- INSERT-only triggers, this is belt-and-suspenders protection.
-- =============================================================================

-- daily_recovery → raw.whoop_cycles
ALTER TABLE normalized.daily_recovery
DROP CONSTRAINT IF EXISTS daily_recovery_raw_id_fkey;

ALTER TABLE normalized.daily_recovery
ADD CONSTRAINT daily_recovery_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.whoop_cycles(id) ON DELETE RESTRICT;

-- daily_sleep → raw.whoop_sleep
ALTER TABLE normalized.daily_sleep
DROP CONSTRAINT IF EXISTS daily_sleep_raw_id_fkey;

ALTER TABLE normalized.daily_sleep
ADD CONSTRAINT daily_sleep_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.whoop_sleep(id) ON DELETE RESTRICT;

-- daily_strain → raw.whoop_strain
ALTER TABLE normalized.daily_strain
DROP CONSTRAINT IF EXISTS daily_strain_raw_id_fkey;

ALTER TABLE normalized.daily_strain
ADD CONSTRAINT daily_strain_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.whoop_strain(id) ON DELETE RESTRICT;

-- body_metrics → raw.healthkit_samples
ALTER TABLE normalized.body_metrics
DROP CONSTRAINT IF EXISTS body_metrics_raw_id_fkey;

ALTER TABLE normalized.body_metrics
ADD CONSTRAINT body_metrics_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.healthkit_samples(id) ON DELETE RESTRICT;

-- transactions → raw.bank_sms
ALTER TABLE normalized.transactions
DROP CONSTRAINT IF EXISTS transactions_raw_id_fkey;

ALTER TABLE normalized.transactions
ADD CONSTRAINT transactions_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.bank_sms(id) ON DELETE RESTRICT;

-- food_log → raw.manual_entries
ALTER TABLE normalized.food_log
DROP CONSTRAINT IF EXISTS food_log_raw_id_fkey;

ALTER TABLE normalized.food_log
ADD CONSTRAINT food_log_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.manual_entries(id) ON DELETE RESTRICT;

-- water_log → raw.manual_entries
ALTER TABLE normalized.water_log
DROP CONSTRAINT IF EXISTS water_log_raw_id_fkey;

ALTER TABLE normalized.water_log
ADD CONSTRAINT water_log_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.manual_entries(id) ON DELETE RESTRICT;

-- mood_log → raw.manual_entries
ALTER TABLE normalized.mood_log
DROP CONSTRAINT IF EXISTS mood_log_raw_id_fkey;

ALTER TABLE normalized.mood_log
ADD CONSTRAINT mood_log_raw_id_fkey
FOREIGN KEY (raw_id) REFERENCES raw.manual_entries(id) ON DELETE RESTRICT;

-- =============================================================================
-- 4. Verification
-- =============================================================================

DO $$
DECLARE
    idx_count INT;
    fk_count INT;
BEGIN
    -- Count new indexes
    SELECT count(*) INTO idx_count
    FROM pg_indexes
    WHERE schemaname = 'normalized'
      AND indexname LIKE 'idx_normalized_%_raw_id';

    -- Count RESTRICT FKs
    SELECT count(*) INTO fk_count
    FROM information_schema.referential_constraints rc
    JOIN information_schema.table_constraints tc
        ON rc.constraint_name = tc.constraint_name
    WHERE tc.table_schema = 'normalized'
      AND rc.delete_rule = 'RESTRICT';

    RAISE NOTICE 'Migration 169 verification: % raw_id indexes, % RESTRICT FKs', idx_count, fk_count;
END $$;

COMMIT;
