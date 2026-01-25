-- Migration: 061_sms_intent_enum.up.sql
-- Purpose: Add SMS intent enum type for structured intent classification
-- Date: 2026-01-25

-- ============================================================================
-- Type: finance.sms_intent
-- Purpose: Enumerated type for SMS transaction intent classification
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sms_intent') THEN
        CREATE TYPE finance.sms_intent AS ENUM (
            'purchase',      -- Debit/credit purchase (expense)
            'refund',        -- Money returned (income)
            'salary',        -- Salary deposit (income)
            'transfer_out',  -- Bank transfer outgoing (expense)
            'transfer_in',   -- Bank transfer incoming (income)
            'atm',           -- ATM withdrawal (expense)
            'decline',       -- Transaction declined (no financial impact)
            'auth',          -- Authorization hold (informational)
            'otp',           -- One-time password (ignored)
            'balance_info',  -- Balance notification (informational)
            'security',      -- Security alert (informational)
            'promo',         -- Marketing/promotional (ignored)
            'ignore'         -- Other non-financial (ignored)
        );
        COMMENT ON TYPE finance.sms_intent IS
        'Enumerated SMS intent types for transaction classification';
    END IF;
END $$;

-- ============================================================================
-- Add sms_intent column to raw_events
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'finance'
        AND table_name = 'raw_events'
        AND column_name = 'sms_intent'
    ) THEN
        ALTER TABLE finance.raw_events
        ADD COLUMN sms_intent finance.sms_intent;

        COMMENT ON COLUMN finance.raw_events.sms_intent IS
        'Classified intent of SMS message using finance.sms_intent enum';
    END IF;
END $$;

-- ============================================================================
-- Add sms_intent column to raw.sms_classifications
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'raw'
        AND table_name = 'sms_classifications'
        AND column_name = 'sms_intent'
    ) THEN
        ALTER TABLE raw.sms_classifications
        ADD COLUMN sms_intent finance.sms_intent;

        COMMENT ON COLUMN raw.sms_classifications.sms_intent IS
        'Structured intent classification using enum type';
    END IF;
END $$;

-- ============================================================================
-- Mapping from canonical_intent to sms_intent
-- ============================================================================

CREATE OR REPLACE FUNCTION finance.map_canonical_to_sms_intent(canonical TEXT)
RETURNS finance.sms_intent AS $$
BEGIN
    RETURN CASE canonical
        WHEN 'FIN_TXN_APPROVED' THEN 'purchase'::finance.sms_intent
        WHEN 'FIN_TXN_REFUND' THEN 'refund'::finance.sms_intent
        WHEN 'FIN_TXN_DECLINED' THEN 'decline'::finance.sms_intent
        WHEN 'FIN_AUTH_CODE' THEN 'otp'::finance.sms_intent
        WHEN 'FIN_SECURITY_ALERT' THEN 'security'::finance.sms_intent
        WHEN 'FIN_INFO_ONLY' THEN 'balance_info'::finance.sms_intent
        WHEN 'IGNORE' THEN 'ignore'::finance.sms_intent
        ELSE 'ignore'::finance.sms_intent
    END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION finance.map_canonical_to_sms_intent(TEXT) IS
'Maps legacy canonical_intent strings to the new sms_intent enum';

-- ============================================================================
-- Backfill sms_intent for existing classifications
-- ============================================================================

UPDATE raw.sms_classifications
SET sms_intent = finance.map_canonical_to_sms_intent(canonical_intent)
WHERE sms_intent IS NULL;

-- Add index for sms_intent
CREATE INDEX IF NOT EXISTS idx_sms_class_sms_intent
ON raw.sms_classifications(sms_intent);
