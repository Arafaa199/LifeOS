-- Migration: 062_raw_events_resolution.up.sql
-- Purpose: Add resolution tracking to raw_events for orphan detection
-- Date: 2026-01-25

-- ============================================================================
-- Add resolution tracking columns
-- ============================================================================

-- resolution_status: tracks whether the raw_event has been resolved
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'finance'
        AND table_name = 'raw_events'
        AND column_name = 'resolution_status'
    ) THEN
        ALTER TABLE finance.raw_events
        ADD COLUMN resolution_status TEXT DEFAULT 'pending'
            CHECK (resolution_status IN ('pending', 'linked', 'ignored', 'failed'));

        COMMENT ON COLUMN finance.raw_events.resolution_status IS
        'Resolution status: pending (new), linked (tx created), ignored (non-financial), failed (error/timeout)';
    END IF;
END $$;

-- resolution_reason: explains why/how it was resolved
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'finance'
        AND table_name = 'raw_events'
        AND column_name = 'resolution_reason'
    ) THEN
        ALTER TABLE finance.raw_events
        ADD COLUMN resolution_reason TEXT;

        COMMENT ON COLUMN finance.raw_events.resolution_reason IS
        'Human-readable explanation of resolution status';
    END IF;
END $$;

-- resolved_at: when the resolution happened
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'finance'
        AND table_name = 'raw_events'
        AND column_name = 'resolved_at'
    ) THEN
        ALTER TABLE finance.raw_events
        ADD COLUMN resolved_at TIMESTAMPTZ;

        COMMENT ON COLUMN finance.raw_events.resolved_at IS
        'Timestamp when this event was resolved';
    END IF;
END $$;

-- source: track where the event came from
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'finance'
        AND table_name = 'raw_events'
        AND column_name = 'source'
    ) THEN
        ALTER TABLE finance.raw_events
        ADD COLUMN source TEXT DEFAULT 'unknown';

        COMMENT ON COLUMN finance.raw_events.source IS
        'Source of the raw event: sms, webhook, manual, receipt, etc.';
    END IF;
END $$;

-- payload (alias for raw_payload for compatibility)
-- Note: raw_payload already exists, just add alias view if needed

-- ============================================================================
-- Create indexes for resolution queries
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_raw_events_pending
ON finance.raw_events(created_at)
WHERE resolution_status = 'pending';

CREATE INDEX IF NOT EXISTS idx_raw_events_resolution_status
ON finance.raw_events(resolution_status);

CREATE INDEX IF NOT EXISTS idx_raw_events_source
ON finance.raw_events(source)
WHERE source IS NOT NULL;

-- ============================================================================
-- Backfill existing records
-- ============================================================================

-- Mark events with linked transactions as 'linked'
UPDATE finance.raw_events
SET resolution_status = 'linked',
    resolution_reason = 'Transaction created',
    resolved_at = created_at
WHERE related_transaction_id IS NOT NULL
  AND resolution_status = 'pending';

-- Mark old events (>15 min) with validation_status='invalid' as 'failed'
UPDATE finance.raw_events
SET resolution_status = 'failed',
    resolution_reason = 'Validation failed: ' || COALESCE(array_to_string(validation_errors, ', '), 'unknown'),
    resolved_at = created_at
WHERE validation_status = 'invalid'
  AND resolution_status = 'pending';

-- Mark events with 'ignored' validation_status as 'ignored'
UPDATE finance.raw_events
SET resolution_status = 'ignored',
    resolution_reason = 'Non-financial or excluded intent',
    resolved_at = created_at
WHERE validation_status = 'ignored'
  AND resolution_status = 'pending';

-- Mark very old pending events (>24h) as failed
UPDATE finance.raw_events
SET resolution_status = 'failed',
    resolution_reason = 'Timeout: no resolution within 24 hours',
    resolved_at = NOW()
WHERE resolution_status = 'pending'
  AND created_at < NOW() - INTERVAL '24 hours';

-- ============================================================================
-- Function to resolve orphan events
-- ============================================================================

CREATE OR REPLACE FUNCTION finance.resolve_orphan_events()
RETURNS TABLE(
    resolved_linked INT,
    resolved_ignored INT,
    resolved_failed INT
) AS $$
DECLARE
    v_linked INT := 0;
    v_ignored INT := 0;
    v_failed INT := 0;
BEGIN
    -- 1. Link events that have matching transactions by client_id
    WITH linked AS (
        UPDATE finance.raw_events re
        SET resolution_status = 'linked',
            related_transaction_id = t.id,
            resolution_reason = 'Matched by client_id',
            resolved_at = NOW()
        FROM finance.transactions t
        WHERE re.resolution_status = 'pending'
          AND re.client_id IS NOT NULL
          AND re.client_id = t.client_id
        RETURNING re.id
    )
    SELECT COUNT(*) INTO v_linked FROM linked;

    -- 2. Mark ignored events (non-financial intent)
    WITH ignored AS (
        UPDATE finance.raw_events
        SET resolution_status = 'ignored',
            resolution_reason = 'Non-financial intent: ' || COALESCE(sms_intent::TEXT, event_type),
            resolved_at = NOW()
        WHERE resolution_status = 'pending'
          AND (
              sms_intent IN ('otp', 'ignore', 'balance_info', 'decline', 'security', 'promo')
              OR validation_status = 'ignored'
          )
        RETURNING id
    )
    SELECT COUNT(*) INTO v_ignored FROM ignored;

    -- 3. Mark failed events (pending > 15 minutes)
    WITH failed AS (
        UPDATE finance.raw_events
        SET resolution_status = 'failed',
            resolution_reason = 'Timeout: no transaction created within 15 minutes',
            resolved_at = NOW()
        WHERE resolution_status = 'pending'
          AND created_at < NOW() - INTERVAL '15 minutes'
        RETURNING id
    )
    SELECT COUNT(*) INTO v_failed FROM failed;

    RETURN QUERY SELECT v_linked, v_ignored, v_failed;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION finance.resolve_orphan_events() IS
'Resolves pending raw_events by linking to transactions, marking as ignored, or failing after timeout. Call periodically.';

-- ============================================================================
-- View: Pending events summary
-- ============================================================================

CREATE OR REPLACE VIEW finance.v_raw_events_health AS
SELECT
    resolution_status,
    COUNT(*) as count,
    MIN(created_at) as oldest,
    MAX(created_at) as newest
FROM finance.raw_events
WHERE created_at >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY resolution_status
ORDER BY
    CASE resolution_status
        WHEN 'pending' THEN 1
        WHEN 'failed' THEN 2
        WHEN 'ignored' THEN 3
        WHEN 'linked' THEN 4
    END;

COMMENT ON VIEW finance.v_raw_events_health IS
'Health dashboard for raw_events resolution status';
