-- Migration 168 Down: Revert to txid-based coalescing
--
-- This restores the migration 142 pattern with STATEMENT triggers

BEGIN;

-- Drop new functions
DROP FUNCTION IF EXISTS life.cleanup_refresh_queue(INT);
DROP FUNCTION IF EXISTS life.process_pending_refreshes(INT, INT);

-- Drop new index
DROP INDEX IF EXISTS life.idx_refresh_queue_pending;

-- Recreate queue table with original structure
DROP TABLE IF EXISTS life.refresh_queue;

CREATE TABLE life.refresh_queue (
    date DATE NOT NULL,
    txid BIGINT NOT NULL DEFAULT txid_current(),
    queued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    source TEXT,
    PRIMARY KEY (date, txid)
);

-- Restore original ROW trigger function with coalescing
CREATE OR REPLACE FUNCTION life.queue_refresh_on_write()
RETURNS TRIGGER AS $$
DECLARE
    target_date DATE;
BEGIN
    IF TG_TABLE_NAME IN ('whoop_recovery', 'whoop_sleep', 'whoop_strain', 'metrics') THEN
        target_date := NEW.date;
    ELSIF TG_TABLE_NAME = 'transactions' THEN
        target_date := (NEW.transaction_at AT TIME ZONE 'Asia/Dubai')::date;
    ELSE
        target_date := CURRENT_DATE;
    END IF;

    INSERT INTO life.refresh_queue (date, source)
    VALUES (target_date, TG_TABLE_NAME)
    ON CONFLICT (date, txid) DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Restore STATEMENT trigger function
CREATE OR REPLACE FUNCTION life.process_refresh_queue()
RETURNS TRIGGER AS $$
DECLARE
    queued_date DATE;
    refresh_result RECORD;
    processed_count INT := 0;
    current_txid BIGINT := txid_current();
BEGIN
    FOR queued_date IN
        SELECT DISTINCT date FROM life.refresh_queue WHERE txid = current_txid
    LOOP
        BEGIN
            SELECT * INTO refresh_result
            FROM life.refresh_daily_facts(queued_date, 'queue_' || TG_TABLE_NAME);
            processed_count := processed_count + 1;
        EXCEPTION WHEN OTHERS THEN
            INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail, row_data)
            VALUES ('process_refresh_queue', TG_TABLE_NAME, SQLERRM, SQLSTATE,
                    jsonb_build_object('date', queued_date, 'txid', current_txid));
            RAISE WARNING 'Queue refresh failed for %: %', queued_date, SQLERRM;
        END;
    END LOOP;

    DELETE FROM life.refresh_queue WHERE txid = current_txid;

    IF processed_count > 0 THEN
        RAISE NOTICE '[%] Processed % queued refresh(es)', TG_TABLE_NAME, processed_count;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Restore STATEMENT triggers
CREATE TRIGGER trg_process_refresh_recovery
    AFTER INSERT OR UPDATE ON health.whoop_recovery
    FOR EACH STATEMENT EXECUTE FUNCTION life.process_refresh_queue();

CREATE TRIGGER trg_process_refresh_sleep
    AFTER INSERT OR UPDATE ON health.whoop_sleep
    FOR EACH STATEMENT EXECUTE FUNCTION life.process_refresh_queue();

CREATE TRIGGER trg_process_refresh_strain
    AFTER INSERT OR UPDATE ON health.whoop_strain
    FOR EACH STATEMENT EXECUTE FUNCTION life.process_refresh_queue();

CREATE TRIGGER trg_process_refresh_metrics
    AFTER INSERT OR UPDATE ON health.metrics
    FOR EACH STATEMENT EXECUTE FUNCTION life.process_refresh_queue();

CREATE TRIGGER trg_process_refresh_transactions
    AFTER INSERT OR UPDATE ON finance.transactions
    FOR EACH STATEMENT EXECUTE FUNCTION life.process_refresh_queue();

COMMIT;
