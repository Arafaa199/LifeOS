-- Migration 125: Backfill normalized tables from legacy WHOOP data
-- Depends on: Migration 124 (triggers now fire on UPDATE)
-- Purpose: Re-trigger propagation from legacy tables to fix stale normalized data

BEGIN;

-- Step 1: Touch all recovery rows to re-fire propagation triggers
-- The AFTER INSERT OR UPDATE trigger (from migration 124) will propagate to raw + normalized
UPDATE health.whoop_recovery SET recovery_score = recovery_score;

-- Step 2: Touch all sleep rows
UPDATE health.whoop_sleep SET time_in_bed_min = time_in_bed_min;

-- Step 3: Touch all strain rows
UPDATE health.whoop_strain SET day_strain = day_strain;

COMMIT;

-- Step 4: Rebuild daily_facts for all dates with WHOOP data
-- This must run outside the transaction because rebuild_daily_facts uses advisory locks
SELECT * FROM life.rebuild_daily_facts('2025-01-01'::date, '2025-12-31'::date, 'migration-125');
SELECT * FROM life.rebuild_daily_facts('2026-01-01'::date, life.dubai_today(), 'migration-125');
