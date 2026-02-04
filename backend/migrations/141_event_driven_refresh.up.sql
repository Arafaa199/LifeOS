-- Migration 141: Event-Driven Daily Facts Refresh
--
-- Problem: Data arrives in source tables but daily_facts is only refreshed by nightly batch.
--          Dashboard shows stale data even when fresh data exists.
--
-- Solution: AFTER INSERT/UPDATE triggers on source tables call refresh_daily_facts()
--           synchronously, ensuring the write is reflected in daily_facts immediately.
--
-- This migration implements the pattern for WHOOP recovery only.
-- Once proven, extend to: whoop_sleep, whoop_strain, health.metrics, finance.transactions

BEGIN;

-- =============================================================================
-- 1. Create trigger function for event-driven refresh
-- =============================================================================

CREATE OR REPLACE FUNCTION life.trigger_refresh_on_write()
RETURNS TRIGGER AS $$
DECLARE
    target_date DATE;
    refresh_result RECORD;
BEGIN
    -- Determine the date to refresh based on table
    -- NOTE: Must use IF/ELSIF, not CASE - PostgreSQL evaluates all CASE branches
    --       which causes "record has no field" errors for columns that don't exist
    IF TG_TABLE_NAME IN ('whoop_recovery', 'whoop_sleep', 'whoop_strain', 'metrics') THEN
        target_date := NEW.date;
    ELSIF TG_TABLE_NAME = 'transactions' THEN
        target_date := (NEW.transaction_at AT TIME ZONE 'Asia/Dubai')::date;
    ELSE
        target_date := CURRENT_DATE;
    END IF;

    -- Call refresh_daily_facts for the affected date
    -- Wrapped in exception handler so write succeeds even if refresh fails
    BEGIN
        SELECT * INTO refresh_result
        FROM life.refresh_daily_facts(target_date, TG_TABLE_NAME || '_trigger');

        -- Log success (optional, for debugging)
        RAISE NOTICE 'Refreshed daily_facts for % via % trigger: %',
            target_date, TG_TABLE_NAME, refresh_result.status;

    EXCEPTION WHEN OTHERS THEN
        -- Log error but don't fail the original write
        INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail, row_data)
        VALUES (
            'trigger_refresh_on_write',
            TG_TABLE_NAME,
            SQLERRM,
            SQLSTATE,
            jsonb_build_object('date', target_date, 'operation', TG_OP)
        );
        RAISE WARNING 'refresh_daily_facts failed for % (via %): %', target_date, TG_TABLE_NAME, SQLERRM;
    END;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION life.trigger_refresh_on_write() IS
'Event-driven trigger function that refreshes daily_facts after source table writes.
Ensures dashboard always reflects latest data. Exception-safe: write succeeds even if refresh fails.
Migration 141.';

-- =============================================================================
-- 2. Add trigger to health.whoop_recovery (MVP - one metric only)
-- =============================================================================

-- Drop if exists (for idempotency during development)
DROP TRIGGER IF EXISTS trg_refresh_facts_on_recovery ON health.whoop_recovery;

CREATE TRIGGER trg_refresh_facts_on_recovery
    AFTER INSERT OR UPDATE ON health.whoop_recovery
    FOR EACH ROW
    EXECUTE FUNCTION life.trigger_refresh_on_write();

COMMENT ON TRIGGER trg_refresh_facts_on_recovery ON health.whoop_recovery IS
'Event-driven refresh: After WHOOP recovery write, immediately refresh daily_facts for that date.
Ensures dashboard shows fresh recovery score without waiting for nightly batch.';

-- =============================================================================
-- 3. Verify: Show current triggers on whoop_recovery
-- =============================================================================

SELECT tgname, tgtype, proname
FROM pg_trigger t
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE tgrelid = 'health.whoop_recovery'::regclass
  AND NOT tgisinternal;

COMMIT;
