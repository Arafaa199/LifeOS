-- Migration: 007_sms_date_quarantine
-- Purpose: Add quarantine system for transactions with suspect dates
-- Date: 2026-01-21
--
-- This migration:
-- 1. Adds is_quarantined and quarantine_reason columns to finance.transactions
-- 2. Creates ops.feature_flags table for feature toggles
-- 3. Creates ops.quarantine_log table for audit trail
-- 4. Creates finance.quarantine_suspect_dates() function to flag bad dates

BEGIN;

-- ============================================================================
-- 1. Add quarantine columns to finance.transactions
-- ============================================================================

ALTER TABLE finance.transactions
ADD COLUMN IF NOT EXISTS is_quarantined BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE finance.transactions
ADD COLUMN IF NOT EXISTS quarantine_reason TEXT;

COMMENT ON COLUMN finance.transactions.is_quarantined IS 'True if this transaction has suspect data and should be excluded from aggregates';
COMMENT ON COLUMN finance.transactions.quarantine_reason IS 'Reason for quarantine (e.g., suspect_year, duplicate, invalid_amount)';

-- Index for efficient filtering of quarantined rows
CREATE INDEX IF NOT EXISTS idx_transactions_quarantined
ON finance.transactions (is_quarantined)
WHERE is_quarantined = TRUE;

-- ============================================================================
-- 2. Create ops.feature_flags table
-- ============================================================================

CREATE TABLE IF NOT EXISTS ops.feature_flags (
    flag_name TEXT PRIMARY KEY,
    enabled BOOLEAN NOT NULL DEFAULT FALSE,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE ops.feature_flags IS 'Feature flags for gradual rollout and killswitches';

-- Insert initial feature flag for SMS quarantine
INSERT INTO ops.feature_flags (flag_name, enabled, description)
VALUES ('sms_quarantine_enabled', TRUE, 'Enable quarantine of SMS transactions with suspect dates')
ON CONFLICT (flag_name) DO NOTHING;

-- ============================================================================
-- 3. Create ops.quarantine_log table
-- ============================================================================

CREATE TABLE IF NOT EXISTS ops.quarantine_log (
    id SERIAL PRIMARY KEY,
    quarantine_run_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reason TEXT NOT NULL,
    rows_affected INTEGER NOT NULL,
    source TEXT NOT NULL DEFAULT 'manual',
    details JSONB
);

COMMENT ON TABLE ops.quarantine_log IS 'Audit trail of quarantine operations';

-- ============================================================================
-- 4. Create quarantine function for suspect dates
-- ============================================================================

CREATE OR REPLACE FUNCTION finance.quarantine_suspect_dates()
RETURNS TABLE (
    quarantined_count INTEGER,
    reason TEXT
) AS $$
DECLARE
    v_before_2020_count INTEGER := 0;
    v_future_count INTEGER := 0;
    v_feature_enabled BOOLEAN;
    v_current_year INTEGER := EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER;
BEGIN
    -- Check feature flag
    SELECT enabled INTO v_feature_enabled
    FROM ops.feature_flags
    WHERE flag_name = 'sms_quarantine_enabled';

    IF NOT COALESCE(v_feature_enabled, FALSE) THEN
        RAISE NOTICE 'SMS quarantine feature flag is disabled';
        quarantined_count := 0;
        reason := 'feature_disabled';
        RETURN NEXT;
        RETURN;
    END IF;

    -- Quarantine transactions before 2020 (Nexus didn't exist)
    WITH updated AS (
        UPDATE finance.transactions
        SET
            is_quarantined = TRUE,
            quarantine_reason = 'suspect_year_before_2020'
        WHERE
            is_quarantined = FALSE
            AND EXTRACT(YEAR FROM date) < 2020
        RETURNING id
    )
    SELECT COUNT(*) INTO v_before_2020_count FROM updated;

    -- Log if any were quarantined
    IF v_before_2020_count > 0 THEN
        INSERT INTO ops.quarantine_log (reason, rows_affected, source, details)
        VALUES (
            'suspect_year_before_2020',
            v_before_2020_count,
            'finance.quarantine_suspect_dates',
            jsonb_build_object('threshold_year', 2020)
        );

        quarantined_count := v_before_2020_count;
        reason := 'suspect_year_before_2020';
        RETURN NEXT;
    END IF;

    -- Quarantine transactions more than 1 year in future
    WITH updated AS (
        UPDATE finance.transactions
        SET
            is_quarantined = TRUE,
            quarantine_reason = 'suspect_year_future'
        WHERE
            is_quarantined = FALSE
            AND EXTRACT(YEAR FROM date) > v_current_year + 1
        RETURNING id
    )
    SELECT COUNT(*) INTO v_future_count FROM updated;

    -- Log if any were quarantined
    IF v_future_count > 0 THEN
        INSERT INTO ops.quarantine_log (reason, rows_affected, source, details)
        VALUES (
            'suspect_year_future',
            v_future_count,
            'finance.quarantine_suspect_dates',
            jsonb_build_object('threshold_year', v_current_year + 1)
        );

        quarantined_count := v_future_count;
        reason := 'suspect_year_future';
        RETURN NEXT;
    END IF;

    -- Return summary if no rows affected
    IF v_before_2020_count = 0 AND v_future_count = 0 THEN
        quarantined_count := 0;
        reason := 'no_suspect_dates_found';
        RETURN NEXT;
    END IF;

    RETURN;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION finance.quarantine_suspect_dates() IS 'Flags transactions with dates before 2020 or more than 1 year in future';

COMMIT;
