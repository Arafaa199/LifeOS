-- Migration 168: Refresh Queue Background-Poll Redesign
--
-- Problem: The txid-based coalescing (migration 142) has a race condition.
--          Transaction A and B both insert data for the same date.
--          A commits → STATEMENT trigger fires → processes queue → deletes entries.
--          B commits → STATEMENT trigger fires → queue is empty → refresh skipped.
--          Result: daily_facts doesn't reflect B's data until next write.
--
-- Solution: Decouple refresh from write transactions entirely.
--   1. ROW trigger: INSERT to queue (no processing, no coalescing)
--   2. Background worker: life.process_pending_refreshes() polled by n8n every 30s
--   3. Advisory lock PER DATE: prevents concurrent refresh of same date
--   4. Per-row success tracking: failed dates stay in queue for retry
--
-- This eliminates the race condition because refresh is no longer tied to
-- the committing transaction's visibility window.

BEGIN;

-- =============================================================================
-- 1. Alter queue table: add processed_at, add id, drop txid-based PK
-- =============================================================================

-- Drop old primary key (date, txid)
ALTER TABLE life.refresh_queue DROP CONSTRAINT IF EXISTS refresh_queue_pkey;

-- Add id column for row-level tracking
ALTER TABLE life.refresh_queue ADD COLUMN IF NOT EXISTS id SERIAL;

-- Add processed_at to track when entries are successfully processed
ALTER TABLE life.refresh_queue ADD COLUMN IF NOT EXISTS processed_at TIMESTAMPTZ;

-- Add failed_at + error for tracking failed refreshes (entries stay for retry)
ALTER TABLE life.refresh_queue ADD COLUMN IF NOT EXISTS failed_at TIMESTAMPTZ;
ALTER TABLE life.refresh_queue ADD COLUMN IF NOT EXISTS error_message TEXT;
ALTER TABLE life.refresh_queue ADD COLUMN IF NOT EXISTS attempt_count INT NOT NULL DEFAULT 0;

-- New PK on id
ALTER TABLE life.refresh_queue ADD PRIMARY KEY (id);

-- Index for efficient pending query (unprocessed, not recently failed)
CREATE INDEX IF NOT EXISTS idx_refresh_queue_pending
    ON life.refresh_queue (date, queued_at)
    WHERE processed_at IS NULL;

-- Drop txid column (no longer needed — we don't coalesce by transaction)
ALTER TABLE life.refresh_queue DROP COLUMN IF EXISTS txid;

COMMENT ON TABLE life.refresh_queue IS
'Queue for daily_facts refresh. Polled by background worker every 30s.
Migration 168: Replaced txid-based coalescing with background-poll + advisory locks.
Entries are marked processed on success or retain failed_at for retry.';

-- =============================================================================
-- 2. Drop old STATEMENT triggers (the source of the race condition)
-- =============================================================================

DROP TRIGGER IF EXISTS trg_process_refresh_recovery ON health.whoop_recovery;
DROP TRIGGER IF EXISTS trg_process_refresh_sleep ON health.whoop_sleep;
DROP TRIGGER IF EXISTS trg_process_refresh_strain ON health.whoop_strain;
DROP TRIGGER IF EXISTS trg_process_refresh_metrics ON health.metrics;
DROP TRIGGER IF EXISTS trg_process_refresh_transactions ON finance.transactions;

-- Drop the old processing function
DROP FUNCTION IF EXISTS life.process_refresh_queue();

-- =============================================================================
-- 3. Simplify ROW trigger: just INSERT, no coalescing, no processing
-- =============================================================================

CREATE OR REPLACE FUNCTION life.queue_refresh_on_write()
RETURNS TRIGGER AS $$
DECLARE
    target_date DATE;
BEGIN
    -- Determine date from the row being written
    IF TG_TABLE_NAME IN ('whoop_recovery', 'whoop_sleep', 'whoop_strain', 'metrics') THEN
        target_date := NEW.date;
    ELSIF TG_TABLE_NAME = 'transactions' THEN
        target_date := (NEW.transaction_at AT TIME ZONE 'Asia/Dubai')::date;
    ELSE
        target_date := CURRENT_DATE;
    END IF;

    -- Simple INSERT — background worker deduplicates by date when processing
    INSERT INTO life.refresh_queue (date, source)
    VALUES (target_date, TG_TABLE_NAME);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION life.queue_refresh_on_write() IS
'Row trigger: queues date for background refresh. No processing here.
Multiple rows for same date = multiple queue entries (deduplicated at processing time).
Migration 168.';

-- =============================================================================
-- 4. Background processing function with advisory lock PER DATE
--    and per-row success/failure tracking
-- =============================================================================

CREATE OR REPLACE FUNCTION life.process_pending_refreshes(
    batch_size INT DEFAULT 100,
    max_attempts INT DEFAULT 5
)
RETURNS TABLE (
    dates_processed INT,
    dates_failed INT,
    dates_skipped INT,
    execution_ms INT
) AS $$
DECLARE
    start_time TIMESTAMPTZ := clock_timestamp();
    d DATE;
    lock_key INT;
    success_count INT := 0;
    fail_count INT := 0;
    skip_count INT := 0;
    pending_dates DATE[];
    row_ids_for_date INT[];
BEGIN
    -- Step 1: Get distinct dates that have unprocessed entries
    --         Exclude dates that failed recently (backoff: wait attempt_count * 30 seconds)
    SELECT array_agg(DISTINCT date)
    INTO pending_dates
    FROM (
        SELECT date
        FROM life.refresh_queue
        WHERE processed_at IS NULL
          AND (failed_at IS NULL
               OR failed_at < NOW() - (attempt_count * INTERVAL '30 seconds'))
          AND attempt_count < max_attempts
        ORDER BY date
        LIMIT batch_size
    ) sub;

    -- Nothing to process
    IF pending_dates IS NULL OR array_length(pending_dates, 1) IS NULL THEN
        RETURN QUERY SELECT 0, 0, 0, 0;
        RETURN;
    END IF;

    -- Step 2: Process each date independently with advisory lock
    FOREACH d IN ARRAY pending_dates
    LOOP
        -- Advisory lock keyed on the date — prevents concurrent refresh of same date
        -- Use hashtext for a stable int from the date string
        lock_key := hashtext('refresh_daily_facts_' || d::text);

        -- Try to acquire lock. If another worker is already refreshing this date, skip it.
        IF NOT pg_try_advisory_xact_lock(lock_key) THEN
            skip_count := skip_count + 1;
            CONTINUE;
        END IF;

        -- Collect all queue row IDs for this date (to mark them after)
        SELECT array_agg(id)
        INTO row_ids_for_date
        FROM life.refresh_queue
        WHERE date = d
          AND processed_at IS NULL
          AND attempt_count < max_attempts;

        IF row_ids_for_date IS NULL THEN
            -- Another worker already processed these between our SELECT and lock
            CONTINUE;
        END IF;

        -- Attempt the refresh
        BEGIN
            PERFORM life.refresh_daily_facts(d, 'background_worker');

            -- SUCCESS: mark all queue entries for this date as processed
            UPDATE life.refresh_queue
            SET processed_at = clock_timestamp()
            WHERE id = ANY(row_ids_for_date);

            success_count := success_count + 1;

        EXCEPTION WHEN OTHERS THEN
            -- FAILURE: increment attempt count, record error, keep in queue for retry
            UPDATE life.refresh_queue
            SET failed_at = clock_timestamp(),
                error_message = SQLERRM,
                attempt_count = attempt_count + 1
            WHERE id = ANY(row_ids_for_date);

            fail_count := fail_count + 1;

            -- Log to ops.trigger_errors for visibility
            INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail, row_data)
            VALUES ('process_pending_refreshes', 'life.refresh_queue', SQLERRM, SQLSTATE,
                    jsonb_build_object('date', d, 'queue_ids', row_ids_for_date));

            RAISE WARNING 'Background refresh failed for %: % (attempt %)',
                d, SQLERRM, (SELECT MAX(attempt_count) FROM life.refresh_queue WHERE id = ANY(row_ids_for_date));
        END;
    END LOOP;

    -- Advisory locks are released automatically at end of transaction (xact lock)

    RETURN QUERY SELECT
        success_count,
        fail_count,
        skip_count,
        EXTRACT(MILLISECONDS FROM clock_timestamp() - start_time)::INT;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION life.process_pending_refreshes(INT, INT) IS
'Background worker for processing refresh queue. Called by n8n every 30 seconds.

Key design decisions:
- Advisory lock PER DATE (not per row): prevents concurrent refresh of same date
  while allowing different dates to be processed in parallel by multiple workers.
- pg_try_advisory_xact_lock: non-blocking, released at end of transaction.
- Failed dates stay in queue with attempt_count + exponential backoff.
- Success marks all queue entries for that date as processed.
- max_attempts prevents infinite retry of permanently broken dates.

Migration 168.';

-- =============================================================================
-- 5. Cleanup function for old processed entries
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

    -- Also clean permanently failed entries (exceeded max attempts)
    DELETE FROM life.refresh_queue
    WHERE processed_at IS NULL
      AND attempt_count >= 5
      AND failed_at < NOW() - INTERVAL '7 days';

    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION life.cleanup_refresh_queue(INT) IS
'Removes old processed queue entries (default: 24h retention).
Also removes permanently failed entries older than 7 days.
Called by n8n nightly cleanup job.';

-- =============================================================================
-- 6. Ensure ROW triggers exist on all source tables
-- =============================================================================

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
