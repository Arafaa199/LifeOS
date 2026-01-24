-- ============================================================================
-- M6.3: raw.sms_events - Structured SMS parsing output
--
-- This view provides a structured interface for SMS classification results.
-- All parsing is done by the regex-first classifier (no LLM).
-- ============================================================================

-- Create enum type for SMS intents (if not exists)
DO $$ BEGIN
    CREATE TYPE raw.sms_intent AS ENUM (
        'TRANSACTION_APPROVED',
        'TRANSACTION_DECLINED',
        'SALARY_CREDIT',
        'REFUND',
        'OTP',
        'TRANSFER',
        'EXCLUDED',
        'UNMATCHED'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Create the sms_events view that structures finance.transactions SMS data
CREATE OR REPLACE VIEW raw.sms_events AS
SELECT
    t.id AS event_id,
    t.external_id,
    SUBSTRING(t.external_id FROM 5)::bigint AS message_id,

    -- Intent mapping from raw_data
    CASE
        WHEN (t.raw_data->>'intent') = 'expense' THEN 'TRANSACTION_APPROVED'::text
        WHEN (t.raw_data->>'intent') = 'income' AND (t.raw_data->>'pattern') ILIKE '%salary%' THEN 'SALARY_CREDIT'::text
        WHEN (t.raw_data->>'intent') = 'income' THEN 'TRANSACTION_APPROVED'::text
        WHEN (t.raw_data->>'intent') = 'refund' THEN 'REFUND'::text
        WHEN (t.raw_data->>'intent') = 'declined' THEN 'TRANSACTION_DECLINED'::text
        WHEN (t.raw_data->>'intent') = 'transfer' THEN 'TRANSFER'::text
        ELSE 'UNMATCHED'::text
    END AS intent,

    -- Amount (absolute value, direction handled separately)
    ABS(t.amount) AS amount,
    t.currency,
    t.merchant_name_clean AS merchant,

    -- Account tail (last 4 digits if available)
    CASE
        WHEN t.raw_data->'entities'->>'card' IS NOT NULL
        THEN t.raw_data->'entities'->>'card'
        ELSE NULL
    END AS account_tail,

    -- Direction derived from amount sign
    CASE
        WHEN t.amount > 0 THEN 'credit'
        WHEN t.amount < 0 THEN 'debit'
        ELSE 'unknown'
    END AS direction,

    -- Language detection based on sender and pattern
    CASE
        WHEN (t.raw_data->>'sender') = 'EmiratesNBD' THEN 'ar'
        WHEN (t.raw_data->>'sender') = 'AlRajhiBank' THEN 'en'
        WHEN (t.raw_data->>'sender') = 'JKB' THEN 'en'
        ELSE 'unknown'
    END AS language,

    -- Confidence from classifier
    COALESCE((t.raw_data->>'confidence')::numeric, 0) AS confidence,

    -- Parser version
    'regex-v1' AS parser_version,

    -- Source metadata
    t.raw_data->>'sender' AS sender,
    t.raw_data->>'pattern' AS pattern_name,
    t.date AS transaction_date,
    t.created_at AS parsed_at

FROM finance.transactions t
WHERE t.external_id LIKE 'sms:%';

COMMENT ON VIEW raw.sms_events IS 'Structured SMS parsing output for M6.3 proof loop. All fields from regex classifier.';

-- Create a summary view for quick verification
CREATE OR REPLACE VIEW raw.sms_events_summary AS
SELECT
    intent,
    direction,
    language,
    COUNT(*) as count,
    SUM(amount) as total_amount,
    AVG(confidence)::numeric(3,2) as avg_confidence,
    MIN(transaction_date) as first_date,
    MAX(transaction_date) as last_date
FROM raw.sms_events
WHERE intent != 'EXCLUDED' AND intent != 'OTP'
GROUP BY intent, direction, language
ORDER BY count DESC;

COMMENT ON VIEW raw.sms_events_summary IS 'Quick summary of SMS parsing results by intent/direction/language';
