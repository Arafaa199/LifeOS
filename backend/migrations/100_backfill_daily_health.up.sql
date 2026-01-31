-- Migration 100: Backfill facts.daily_health with all WHOOP + HealthKit data
-- TASK-PLAN.8: Ensure complete historical coverage
--
-- Strategy:
-- 1. Delete empty placeholder rows (no real data)
-- 2. Re-run refresh_daily_health for every date that has source data
-- 3. Uses ON CONFLICT DO UPDATE (inside refresh function) so safe to re-run

BEGIN;

-- Step 1: Remove placeholder rows that have no actual data
-- These were created by date-range backfills but contain all NULLs
DELETE FROM facts.daily_health
WHERE recovery_score IS NULL
  AND hrv IS NULL
  AND rhr IS NULL
  AND steps IS NULL
  AND weight_kg IS NULL
  AND calories_burned IS NULL
  AND sleep_hours IS NULL
  AND day_strain IS NULL
  AND mood_score IS NULL;

-- Step 2: Backfill from all source dates
-- Collects every distinct date from WHOOP + HealthKit sources
DO $$
DECLARE
    d date;
    cnt_before integer;
    cnt_after integer;
BEGIN
    SELECT COUNT(*) INTO cnt_before FROM facts.daily_health;
    RAISE NOTICE 'facts.daily_health before backfill: % rows', cnt_before;

    FOR d IN
        SELECT DISTINCT source_date FROM (
            SELECT date AS source_date FROM health.whoop_recovery
            UNION
            SELECT date AS source_date FROM health.whoop_sleep
            UNION
            SELECT date AS source_date FROM health.whoop_strain
            UNION
            SELECT DISTINCT (start_date AT TIME ZONE 'Asia/Dubai')::date AS source_date
            FROM raw.healthkit_samples
            WHERE sample_type IN (
                'HKQuantityTypeIdentifierStepCount',
                'HKQuantityTypeIdentifierBodyMass',
                'HKQuantityTypeIdentifierActiveEnergyBurned',
                'HKQuantityTypeIdentifierHeartRateVariabilitySDNN',
                'HKQuantityTypeIdentifierRestingHeartRate'
            )
        ) all_dates
        ORDER BY source_date
    LOOP
        BEGIN
            PERFORM facts.refresh_daily_health(d);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Error refreshing %: %', d, SQLERRM;
        END;
    END LOOP;

    SELECT COUNT(*) INTO cnt_after FROM facts.daily_health;
    RAISE NOTICE 'facts.daily_health after backfill: % rows (was %)', cnt_after, cnt_before;
END;
$$;

COMMIT;
