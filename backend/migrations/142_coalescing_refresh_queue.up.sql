-- Migration 142: Coalescing Refresh Queue
--
-- Problem: Migration 141's trigger calls refresh_daily_facts() for EVERY row write.
--          A 100-row bulk insert = 100 refreshes. Wasteful.
--
-- Solution: Two-phase trigger pattern:
--   1. ROW trigger: Queue the date (ON CONFLICT DO NOTHING = coalesce)
--   2. STATEMENT trigger: Process queue once after all rows are done
--
-- Transaction-safe: Queue keyed by (date, txid) so concurrent transactions
-- don't interfere with each other.

BEGIN;

-- =============================================================================
-- 1. Create queue table (transaction-aware)
-- =============================================================================

CREATE TABLE life.refresh_queue (
    date DATE NOT NULL,
    txid BIGINT NOT NULL DEFAULT txid_current(),
    queued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    source TEXT,
    PRIMARY KEY (date, txid)
);

COMMENT ON TABLE life.refresh_queue IS
'Coalescing queue for daily_facts refresh.
Multiple writes to same date in same transaction = one refresh.
Keyed by (date, txid) for transaction isolation.
Migration 142.';

-- =============================================================================
-- 2. Row trigger function: queue the date (coalesces within transaction)
-- =============================================================================

CREATE OR REPLACE FUNCTION life.queue_refresh_on_write()
RETURNS TRIGGER AS $$
DECLARE
    target_date DATE;
BEGIN
    -- Determine date based on table
    IF TG_TABLE_NAME IN ('whoop_recovery', 'whoop_sleep', 'whoop_strain', 'metrics') THEN
        target_date := NEW.date;
    ELSIF TG_TABLE_NAME = 'transactions' THEN
        target_date := (NEW.transaction_at AT TIME ZONE 'Asia/Dubai')::date;
    ELSE
        target_date := CURRENT_DATE;
    END IF;

    -- Queue the date (ON CONFLICT = coalesce duplicates within same transaction)
    INSERT INTO life.refresh_queue (date, source)
    VALUES (target_date, TG_TABLE_NAME)
    ON CONFLICT (date, txid) DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION life.queue_refresh_on_write() IS
'Row trigger: queues date for refresh. Coalesces via ON CONFLICT DO NOTHING.
100 rows with same date = 1 queue entry.';

-- =============================================================================
-- 3. Statement trigger function: process queue for this transaction
-- =============================================================================

CREATE OR REPLACE FUNCTION life.process_refresh_queue()
RETURNS TRIGGER AS $$
DECLARE
    queued_date DATE;
    refresh_result RECORD;
    processed_count INT := 0;
    current_txid BIGINT := txid_current();
BEGIN
    -- Process all dates queued by THIS transaction only
    FOR queued_date IN
        SELECT DISTINCT date FROM life.refresh_queue WHERE txid = current_txid
    LOOP
        BEGIN
            SELECT * INTO refresh_result
            FROM life.refresh_daily_facts(queued_date, 'queue_' || TG_TABLE_NAME);
            processed_count := processed_count + 1;
        EXCEPTION WHEN OTHERS THEN
            -- Log error but don't fail the transaction
            INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail, row_data)
            VALUES ('process_refresh_queue', TG_TABLE_NAME, SQLERRM, SQLSTATE,
                    jsonb_build_object('date', queued_date, 'txid', current_txid));
            RAISE WARNING 'Queue refresh failed for %: %', queued_date, SQLERRM;
        END;
    END LOOP;

    -- Clean up queue entries for this transaction
    DELETE FROM life.refresh_queue WHERE txid = current_txid;

    IF processed_count > 0 THEN
        RAISE NOTICE '[%] Processed % queued refresh(es)', TG_TABLE_NAME, processed_count;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION life.process_refresh_queue() IS
'Statement trigger: processes queued dates after all rows are written.
Only processes entries for current transaction (txid isolation).
Cleans up queue after processing.';

-- =============================================================================
-- 4. Drop old synchronous trigger from migration 141
-- =============================================================================

DROP TRIGGER IF EXISTS trg_refresh_facts_on_recovery ON health.whoop_recovery;

-- =============================================================================
-- 5. Apply queue triggers to all source tables
-- =============================================================================

-- WHOOP Recovery
CREATE TRIGGER trg_queue_refresh_recovery
    AFTER INSERT OR UPDATE ON health.whoop_recovery
    FOR EACH ROW EXECUTE FUNCTION life.queue_refresh_on_write();

CREATE TRIGGER trg_process_refresh_recovery
    AFTER INSERT OR UPDATE ON health.whoop_recovery
    FOR EACH STATEMENT EXECUTE FUNCTION life.process_refresh_queue();

-- WHOOP Sleep
CREATE TRIGGER trg_queue_refresh_sleep
    AFTER INSERT OR UPDATE ON health.whoop_sleep
    FOR EACH ROW EXECUTE FUNCTION life.queue_refresh_on_write();

CREATE TRIGGER trg_process_refresh_sleep
    AFTER INSERT OR UPDATE ON health.whoop_sleep
    FOR EACH STATEMENT EXECUTE FUNCTION life.process_refresh_queue();

-- WHOOP Strain
CREATE TRIGGER trg_queue_refresh_strain
    AFTER INSERT OR UPDATE ON health.whoop_strain
    FOR EACH ROW EXECUTE FUNCTION life.queue_refresh_on_write();

CREATE TRIGGER trg_process_refresh_strain
    AFTER INSERT OR UPDATE ON health.whoop_strain
    FOR EACH STATEMENT EXECUTE FUNCTION life.process_refresh_queue();

-- Health Metrics (weight)
CREATE TRIGGER trg_queue_refresh_metrics
    AFTER INSERT OR UPDATE ON health.metrics
    FOR EACH ROW EXECUTE FUNCTION life.queue_refresh_on_write();

CREATE TRIGGER trg_process_refresh_metrics
    AFTER INSERT OR UPDATE ON health.metrics
    FOR EACH STATEMENT EXECUTE FUNCTION life.process_refresh_queue();

-- Finance Transactions
CREATE TRIGGER trg_queue_refresh_transactions
    AFTER INSERT OR UPDATE ON finance.transactions
    FOR EACH ROW EXECUTE FUNCTION life.queue_refresh_on_write();

CREATE TRIGGER trg_process_refresh_transactions
    AFTER INSERT OR UPDATE ON finance.transactions
    FOR EACH STATEMENT EXECUTE FUNCTION life.process_refresh_queue();

-- =============================================================================
-- 6. Verify triggers are installed
-- =============================================================================

SELECT
    c.relname AS table_name,
    t.tgname AS trigger_name,
    CASE t.tgtype & 1 WHEN 1 THEN 'ROW' ELSE 'STATEMENT' END AS level
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname IN ('health', 'finance')
  AND t.tgname LIKE 'trg_%refresh%'
ORDER BY c.relname, t.tgname;

COMMIT;
