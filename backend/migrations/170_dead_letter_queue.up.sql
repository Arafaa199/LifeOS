-- Migration 170: Dead Letter Queue + Resilience Infrastructure
--
-- Adds a dead letter queue for failed webhook/pipeline operations.
-- Failed operations are captured with full context for retry or diagnosis.
-- Includes a cleanup function to purge resolved entries.

BEGIN;

-- =============================================================================
-- 1. DEAD LETTER QUEUE TABLE
-- =============================================================================

CREATE TABLE IF NOT EXISTS ops.dead_letter_queue (
    id BIGSERIAL PRIMARY KEY,
    -- What failed
    source TEXT NOT NULL,                -- 'webhook', 'pipeline', 'sync', 'cron'
    operation TEXT NOT NULL,             -- e.g. 'nexus-food-log', 'whoop_etl', 'calendar_sync'
    endpoint TEXT,                       -- webhook path or function name

    -- Error info
    error_message TEXT NOT NULL,
    error_code TEXT,                     -- HTTP status, SQLSTATE, etc.
    error_detail TEXT,                   -- stack trace or extra context

    -- Payload for replay
    request_payload JSONB,               -- original request body
    request_headers JSONB,               -- original headers (sans auth)

    -- Retry tracking
    attempt_count INT NOT NULL DEFAULT 1,
    max_attempts INT NOT NULL DEFAULT 5,
    next_retry_at TIMESTAMPTZ,           -- NULL = no auto-retry
    last_retry_at TIMESTAMPTZ,

    -- Resolution
    status TEXT NOT NULL DEFAULT 'pending',  -- pending, retrying, resolved, discarded
    resolved_at TIMESTAMPTZ,
    resolved_by TEXT,                    -- 'auto_retry', 'manual', 'cleanup'
    resolution_note TEXT,

    -- Metadata
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Prevent exact duplicate entries within 1 minute
    CONSTRAINT dlq_no_rapid_dupes UNIQUE (source, operation, error_message, (created_at::date))
);

COMMENT ON TABLE ops.dead_letter_queue IS 'Dead letter queue for failed operations. Entries stay for retry or manual resolution.';

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_dlq_status_retry
    ON ops.dead_letter_queue (status, next_retry_at)
    WHERE status IN ('pending', 'retrying');

CREATE INDEX IF NOT EXISTS idx_dlq_source_operation
    ON ops.dead_letter_queue (source, operation, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_dlq_created
    ON ops.dead_letter_queue (created_at DESC);

-- Auto-update updated_at
CREATE TRIGGER set_updated_at_dlq
    BEFORE UPDATE ON ops.dead_letter_queue
    FOR EACH ROW EXECUTE FUNCTION normalized.update_updated_at();

-- =============================================================================
-- 2. ENQUEUE FUNCTION (called by n8n error handlers and PL/pgSQL)
-- =============================================================================

CREATE OR REPLACE FUNCTION ops.enqueue_dead_letter(
    p_source TEXT,
    p_operation TEXT,
    p_error_message TEXT,
    p_error_code TEXT DEFAULT NULL,
    p_error_detail TEXT DEFAULT NULL,
    p_request_payload JSONB DEFAULT NULL,
    p_endpoint TEXT DEFAULT NULL,
    p_max_attempts INT DEFAULT 5
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    dlq_id BIGINT;
    backoff_minutes INT;
BEGIN
    -- Exponential backoff: 1m, 2m, 4m, 8m, 16m
    backoff_minutes := 1;

    INSERT INTO ops.dead_letter_queue (
        source, operation, endpoint,
        error_message, error_code, error_detail,
        request_payload, max_attempts,
        next_retry_at
    ) VALUES (
        p_source, p_operation, p_endpoint,
        p_error_message, p_error_code, p_error_detail,
        p_request_payload, p_max_attempts,
        NOW() + (backoff_minutes || ' minutes')::interval
    )
    ON CONFLICT ON CONSTRAINT dlq_no_rapid_dupes DO UPDATE
    SET attempt_count = ops.dead_letter_queue.attempt_count + 1,
        updated_at = NOW()
    RETURNING id INTO dlq_id;

    RETURN dlq_id;
END;
$$;

-- =============================================================================
-- 3. RETRY PROCESSOR (called by n8n every 5 minutes)
-- =============================================================================

CREATE OR REPLACE FUNCTION ops.process_dead_letter_retries(batch_size INT DEFAULT 20)
RETURNS TABLE(
    retried INT,
    resolved INT,
    discarded INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    item RECORD;
    retry_count INT := 0;
    resolve_count INT := 0;
    discard_count INT := 0;
BEGIN
    FOR item IN
        SELECT id, source, operation, endpoint, request_payload,
               attempt_count, max_attempts
        FROM ops.dead_letter_queue
        WHERE status IN ('pending', 'retrying')
          AND next_retry_at <= NOW()
        ORDER BY created_at ASC
        LIMIT batch_size
        FOR UPDATE SKIP LOCKED
    LOOP
        IF item.attempt_count >= item.max_attempts THEN
            -- Max retries exhausted → discard
            UPDATE ops.dead_letter_queue
            SET status = 'discarded',
                resolved_at = NOW(),
                resolved_by = 'max_retries',
                updated_at = NOW()
            WHERE id = item.id;
            discard_count := discard_count + 1;
        ELSE
            -- Mark as retrying with exponential backoff for next attempt
            UPDATE ops.dead_letter_queue
            SET status = 'retrying',
                attempt_count = attempt_count + 1,
                last_retry_at = NOW(),
                next_retry_at = NOW() + (power(2, attempt_count) || ' minutes')::interval,
                updated_at = NOW()
            WHERE id = item.id;
            retry_count := retry_count + 1;
        END IF;
    END LOOP;

    RETURN QUERY SELECT retry_count, resolve_count, discard_count;
END;
$$;

-- =============================================================================
-- 4. CLEANUP FUNCTION (purge resolved/discarded entries older than 30 days)
-- =============================================================================

CREATE OR REPLACE FUNCTION ops.cleanup_dead_letters(retention_days INT DEFAULT 30)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    deleted INT;
BEGIN
    DELETE FROM ops.dead_letter_queue
    WHERE status IN ('resolved', 'discarded')
      AND resolved_at < NOW() - (retention_days || ' days')::interval;
    GET DIAGNOSTICS deleted = ROW_COUNT;

    IF deleted > 0 THEN
        RAISE NOTICE 'Cleaned up % dead letter entries older than % days', deleted, retention_days;
    END IF;

    RETURN deleted;
END;
$$;

-- =============================================================================
-- 5. DLQ SUMMARY VIEW (for dashboards)
-- =============================================================================

CREATE OR REPLACE VIEW ops.v_dlq_summary AS
SELECT
    source,
    operation,
    status,
    COUNT(*) AS entry_count,
    MAX(created_at) AS latest_entry,
    MIN(created_at) AS oldest_entry,
    AVG(attempt_count) AS avg_attempts
FROM ops.dead_letter_queue
GROUP BY source, operation, status
ORDER BY entry_count DESC;

COMMIT;
