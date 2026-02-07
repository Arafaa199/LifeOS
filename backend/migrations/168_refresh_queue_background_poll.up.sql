-- Migration 168: Refresh Queue Background Poll Redesign
--
-- Problem: The txid-based coalescing in migration 142 silently skips refreshes
--          when two transactions commit near-simultaneously for the same date.
--          Each transaction only sees its own queue entries, so if transaction A
--          commits and clears the queue while transaction B is still writing,
--          B's refresh might never happen.
--
-- Solution: Replace STATEMENT triggers with a background-poll approach:
--   1. Simple ROW trigger: INSERT to queue (no processing)
--   2. Background worker: life.process_pending_refreshes() called by n8n every 30s
--   3. FOR UPDATE SKIP LOCKED: Safe concurrent processing
--
-- This decouples write latency from refresh processing and eliminates race conditions.

BEGIN;

-- =============================================================================
-- 1. Alter queue table: add processed_at, change PK strategy
-- =============================================================================

-- Drop old primary key (date, txid) - we're changing the model
ALTER TABLE life.refresh_queue DROP CONSTRAINT IF EXISTS refresh_queue_pkey;

-- Add id column for simpler row identification
ALTER TABLE life.refresh_queue ADD COLUMN IF NOT EXISTS id SERIAL;

-- Add processed_at to track when entries are processed
ALTER TABLE life.refresh_queue ADD COLUMN IF NOT EXISTS processed_at TIMESTAMPTZ;

-- New PK on id
ALTER TABLE life.refresh_queue ADD PRIMARY KEY (id);

-- Index for efficient pending query
CREATE INDEX IF NOT EXISTS idx_refresh_queue_pending
    ON life.refresh_queue (date, queued_at)
    WHERE processed_at IS NULL;

-- Drop txid column (no longer needed)
ALTER TABLE life.refresh_queue DROP COLUMN IF EXISTS txid;

COMMENT ON TABLE life.refresh_queue IS
'Queue for daily_facts refresh. Processed by background worker every 30s.
Migration 168: Replaced txid-based coalescing with background-poll pattern.';

-- =============================================================================
-- 2. Drop old STATEMENT triggers (no longer needed)
-- =============================================================================

DROP TRIGGER IF EXISTS trg_process_refresh_recovery ON health.whoop_recovery;
DROP TRIGGER IF EXISTS trg_process_refresh_sleep ON health.whoop_sleep;
DROP TRIGGER IF EXISTS trg_process_refresh_strain ON health.whoop_strain;
DROP TRIGGER IF EXISTS trg_process_refresh_metrics ON health.metrics;
DROP TRIGGER IF EXISTS trg_process_refresh_transactions ON finance.transactions;

-- Drop the old processing function
DROP FUNCTION IF EXISTS life.process_refresh_queue();

-- =============================================================================
-- 3. Simplify ROW trigger: just insert, no coalescing logic
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

    -- Simple insert - background worker will dedupe by date
    INSERT INTO life.refresh_queue (date, source)
    VALUES (target_date, TG_TABLE_NAME);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION life.queue_refresh_on_write() IS
'Row trigger: queues date for background refresh processing.
Simple INSERT - deduplication happens in process_pending_refreshes().
Migration 168.';

-- =============================================================================
-- 4. Create background processing function with FOR UPDATE SKIP LOCKED
-- =============================================================================

CREATE OR REPLACE FUNCTION life.process_pending_refreshes(
    batch_size INT DEFAULT 100
)
RETURNS TABLE (
    dates_processed INT,
    dates_failed INT,
    execution_ms INT
) AS $$
DECLARE
    start_time TIMESTAMPTZ := clock_timestamp();
    queued_dates DATE[];
    d DATE;
    success_count INT := 0;
    fail_count INT := 0;
    locked_ids INT[];
BEGIN
    -- Lock and fetch pending entries (FOR UPDATE SKIP LOCKED = concurrent-safe)
    -- Group by date to avoid redundant refreshes
    WITH locked AS (
        SELECT id, date
        FROM life.refresh_queue
        WHERE processed_at IS NULL
        ORDER BY queued_at
        LIMIT batch_size
        FOR UPDATE SKIP LOCKED
    ),
    distinct_dates AS (
        SELECT DISTINCT date FROM locked
    ),
    all_locked_ids AS (
        SELECT array_agg(id) AS ids FROM locked
    )
    SELECT
        array_agg(DISTINCT dd.date),
        ali.ids
    INTO queued_dates, locked_ids
    FROM distinct_dates dd, all_locked_ids ali
    GROUP BY ali.ids;

    -- Nothing to process
    IF queued_dates IS NULL OR array_length(queued_dates, 1) IS NULL THEN
        RETURN QUERY SELECT 0, 0, 0;
        RETURN;
    END IF;

    -- Process each unique date
    FOREACH d IN ARRAY queued_dates
    LOOP
        BEGIN
            PERFORM life.refresh_daily_facts(d, 'background_worker');
            success_count := success_count + 1;
        EXCEPTION WHEN OTHERS THEN
            fail_count := fail_count + 1;
            -- Log error but continue processing other dates
            INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail, row_data)
            VALUES ('process_pending_refreshes', 'life.refresh_queue', SQLERRM, SQLSTATE,
                    jsonb_build_object('date', d));
            RAISE WARNING 'Background refresh failed for %: %', d, SQLERRM;
        END;
    END LOOP;

    -- Mark all locked entries as processed
    UPDATE life.refresh_queue
    SET processed_at = clock_timestamp()
    WHERE id = ANY(locked_ids);

    -- Return stats
    RETURN QUERY SELECT
        success_count,
        fail_count,
        EXTRACT(MILLISECONDS FROM clock_timestamp() - start_time)::INT;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION life.process_pending_refreshes(INT) IS
'Background worker function for processing refresh queue.
Called by n8n every 30 seconds.

Features:
- FOR UPDATE SKIP LOCKED: Multiple workers can run safely
- Dedupes by date: Multiple queue entries for same date = 1 refresh
- Error resilient: Failed dates logged, others continue processing
- Returns stats: dates_processed, dates_failed, execution_ms

Migration 168.';

-- =============================================================================
-- 5. Create cleanup function for old processed entries
-- =============================================================================

CREATE OR REPLACE FUNCTION life.cleanup_refresh_queue(
    retention_hours INT DEFAULT 24
)
RETURNS INT AS $$
DECLARE
    deleted_count INT;
BEGIN
    DELETE FROM life.refresh_queue
    WHERE processed_at IS NOT NULL
      AND processed_at < NOW() - (retention_hours || ' hours')::INTERVAL;

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION life.cleanup_refresh_queue(INT) IS
'Removes old processed queue entries. Default: keep 24 hours.
Can be called by n8n daily cleanup job.';

-- =============================================================================
-- 6. Verify ROW triggers still exist (re-create if needed)
-- =============================================================================

-- These should already exist from migration 142, but ensure they're there
DO $$
BEGIN
    -- WHOOP Recovery
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_queue_refresh_recovery') THEN
        CREATE TRIGGER trg_queue_refresh_recovery
            AFTER INSERT OR UPDATE ON health.whoop_recovery
            FOR EACH ROW EXECUTE FUNCTION life.queue_refresh_on_write();
    END IF;

    -- WHOOP Sleep
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_queue_refresh_sleep') THEN
        CREATE TRIGGER trg_queue_refresh_sleep
            AFTER INSERT OR UPDATE ON health.whoop_sleep
            FOR EACH ROW EXECUTE FUNCTION life.queue_refresh_on_write();
    END IF;

    -- WHOOP Strain
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_queue_refresh_strain') THEN
        CREATE TRIGGER trg_queue_refresh_strain
            AFTER INSERT OR UPDATE ON health.whoop_strain
            FOR EACH ROW EXECUTE FUNCTION life.queue_refresh_on_write();
    END IF;

    -- Health Metrics
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_queue_refresh_metrics') THEN
        CREATE TRIGGER trg_queue_refresh_metrics
            AFTER INSERT OR UPDATE ON health.metrics
            FOR EACH ROW EXECUTE FUNCTION life.queue_refresh_on_write();
    END IF;

    -- Finance Transactions
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_queue_refresh_transactions') THEN
        CREATE TRIGGER trg_queue_refresh_transactions
            AFTER INSERT OR UPDATE ON finance.transactions
            FOR EACH ROW EXECUTE FUNCTION life.queue_refresh_on_write();
    END IF;
END $$;

-- =============================================================================
-- 7. Process any existing unprocessed entries now
-- =============================================================================

SELECT * FROM life.process_pending_refreshes();

COMMIT;
