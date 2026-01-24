-- Migration: 043_sms_canonical_intents.up.sql
-- Purpose: Add canonical intent classification and coverage tracking for SMS
-- Date: 2026-01-25
--
-- Canonical Intents:
--   FIN_TXN_APPROVED - Financial transaction approved (debit/credit)
--   FIN_TXN_DECLINED - Transaction declined
--   FIN_TXN_REFUND   - Refund received
--   FIN_BALANCE_UPDATE - Balance notification
--   FIN_AUTH_CODE    - OTP/verification codes
--   FIN_SECURITY_ALERT - Security alerts
--   FIN_LOGIN_ALERT  - Login notifications
--   FIN_INFO_ONLY    - Informational (statements, promos)
--   IGNORE           - Not from tracked sender or malformed

-- ============================================================================
-- Table: raw.sms_classifications
-- Purpose: Track intent classification for every SMS message
-- ============================================================================
CREATE TABLE IF NOT EXISTS raw.sms_classifications (
    id BIGSERIAL PRIMARY KEY,
    message_id VARCHAR(255) NOT NULL,
    sender VARCHAR(100) NOT NULL,
    received_at TIMESTAMPTZ NOT NULL,

    -- Classification
    canonical_intent VARCHAR(50) NOT NULL,
    legacy_intent VARCHAR(50),  -- Maps to old intent (expense, income, etc.)
    pattern_name VARCHAR(100),
    confidence NUMERIC(3,2) DEFAULT 0.00,

    -- Extracted data (only for FIN_TXN_* intents)
    amount NUMERIC(15,2),
    currency VARCHAR(10),
    merchant VARCHAR(255),

    -- Status
    created_transaction BOOLEAN DEFAULT FALSE,
    transaction_id INTEGER REFERENCES finance.transactions(id),

    -- Audit
    classified_at TIMESTAMPTZ DEFAULT NOW(),
    classifier_version VARCHAR(20) DEFAULT 'v1.0',

    -- Dedupe
    UNIQUE(message_id)
);

CREATE INDEX IF NOT EXISTS idx_sms_class_intent ON raw.sms_classifications(canonical_intent);
CREATE INDEX IF NOT EXISTS idx_sms_class_date ON raw.sms_classifications(received_at);
CREATE INDEX IF NOT EXISTS idx_sms_class_created_tx ON raw.sms_classifications(created_transaction);

COMMENT ON TABLE raw.sms_classifications IS
'Tracks intent classification for every SMS message.
Enables coverage analysis: "Were there SMS that should have produced transactions but didnt?"';

-- ============================================================================
-- Intent mapping reference
-- ============================================================================
CREATE TABLE IF NOT EXISTS raw.intent_mapping (
    legacy_intent VARCHAR(50) PRIMARY KEY,
    canonical_intent VARCHAR(50) NOT NULL,
    should_create_transaction BOOLEAN NOT NULL,
    description TEXT
);

INSERT INTO raw.intent_mapping VALUES
    ('expense', 'FIN_TXN_APPROVED', TRUE, 'Purchase/debit transaction'),
    ('income', 'FIN_TXN_APPROVED', TRUE, 'Salary/credit received'),
    ('transfer', 'FIN_TXN_APPROVED', TRUE, 'Bank transfer'),
    ('refund', 'FIN_TXN_REFUND', TRUE, 'Refund received'),
    ('declined', 'FIN_TXN_DECLINED', FALSE, 'Transaction declined'),
    ('atm', 'FIN_TXN_APPROVED', TRUE, 'ATM withdrawal'),
    ('otp', 'FIN_AUTH_CODE', FALSE, 'OTP/verification code'),
    ('security', 'FIN_SECURITY_ALERT', FALSE, 'Security alert'),
    ('login', 'FIN_LOGIN_ALERT', FALSE, 'Login notification'),
    ('info', 'FIN_INFO_ONLY', FALSE, 'Informational message'),
    ('balance', 'FIN_BALANCE_UPDATE', FALSE, 'Balance notification'),
    ('promo', 'IGNORE', FALSE, 'Marketing/promotional')
ON CONFLICT (legacy_intent) DO UPDATE SET
    canonical_intent = EXCLUDED.canonical_intent,
    should_create_transaction = EXCLUDED.should_create_transaction;

-- ============================================================================
-- View: raw.sms_daily_coverage
-- Purpose: Answer "Were there SMS that should have produced transactions but didn't?"
-- ============================================================================
CREATE OR REPLACE VIEW raw.sms_daily_coverage AS
WITH daily_stats AS (
    SELECT
        DATE(received_at AT TIME ZONE 'Asia/Dubai') AS day,

        -- Total messages
        COUNT(*) AS total_messages,

        -- By canonical intent
        COUNT(*) FILTER (WHERE canonical_intent = 'FIN_TXN_APPROVED') AS approved_count,
        COUNT(*) FILTER (WHERE canonical_intent = 'FIN_TXN_DECLINED') AS declined_count,
        COUNT(*) FILTER (WHERE canonical_intent = 'FIN_TXN_REFUND') AS refund_count,
        COUNT(*) FILTER (WHERE canonical_intent = 'FIN_AUTH_CODE') AS otp_count,
        COUNT(*) FILTER (WHERE canonical_intent = 'FIN_SECURITY_ALERT') AS security_count,
        COUNT(*) FILTER (WHERE canonical_intent = 'FIN_INFO_ONLY') AS info_count,
        COUNT(*) FILTER (WHERE canonical_intent = 'IGNORE') AS ignored_count,

        -- Should have created transaction
        COUNT(*) FILTER (WHERE canonical_intent IN ('FIN_TXN_APPROVED', 'FIN_TXN_REFUND')) AS should_have_tx,

        -- Actually created transaction
        COUNT(*) FILTER (WHERE created_transaction = TRUE) AS did_create_tx,

        -- GAPS: Should have but didn't
        COUNT(*) FILTER (
            WHERE canonical_intent IN ('FIN_TXN_APPROVED', 'FIN_TXN_REFUND')
              AND created_transaction = FALSE
        ) AS missing_tx_count

    FROM raw.sms_classifications
    GROUP BY DATE(received_at AT TIME ZONE 'Asia/Dubai')
)
SELECT
    day,
    total_messages,
    approved_count,
    declined_count,
    refund_count,
    otp_count + security_count + info_count AS non_financial_count,
    should_have_tx,
    did_create_tx,
    missing_tx_count,

    -- Coverage score: 1.0 = perfect, <1.0 = gaps
    CASE
        WHEN should_have_tx = 0 THEN 1.00
        ELSE ROUND(did_create_tx::NUMERIC / should_have_tx, 2)
    END AS coverage_score,

    -- Status
    CASE
        WHEN missing_tx_count = 0 THEN 'COMPLETE'
        WHEN missing_tx_count <= 2 THEN 'MINOR_GAPS'
        ELSE 'GAPS_DETECTED'
    END AS coverage_status

FROM daily_stats
ORDER BY day DESC;

COMMENT ON VIEW raw.sms_daily_coverage IS
'Daily SMS coverage analysis. Shows whether all financial SMS created transactions.
coverage_score = 1.0 means all financial SMS produced transactions.';

-- ============================================================================
-- View: raw.sms_missing_transactions
-- Purpose: Show specific messages that should have created transactions but didn't
-- ============================================================================
CREATE OR REPLACE VIEW raw.sms_missing_transactions AS
SELECT
    id,
    message_id,
    sender,
    received_at,
    canonical_intent,
    pattern_name,
    amount,
    currency,
    merchant,
    confidence,
    classified_at
FROM raw.sms_classifications
WHERE canonical_intent IN ('FIN_TXN_APPROVED', 'FIN_TXN_REFUND')
  AND created_transaction = FALSE
ORDER BY received_at DESC;

COMMENT ON VIEW raw.sms_missing_transactions IS
'SMS messages that were classified as financial but did not create transactions.
These are gaps that need to be backfilled.';

-- ============================================================================
-- View: raw.sms_coverage_summary
-- Purpose: Overall coverage summary for dashboard
-- ============================================================================
CREATE OR REPLACE VIEW raw.sms_coverage_summary AS
SELECT
    COUNT(DISTINCT day) AS days_tracked,
    SUM(total_messages) AS total_messages,
    SUM(should_have_tx) AS total_should_have_tx,
    SUM(did_create_tx) AS total_did_create_tx,
    SUM(missing_tx_count) AS total_missing,

    CASE
        WHEN SUM(should_have_tx) = 0 THEN 1.00
        ELSE ROUND(SUM(did_create_tx)::NUMERIC / SUM(should_have_tx), 3)
    END AS overall_coverage,

    COUNT(*) FILTER (WHERE coverage_status = 'GAPS_DETECTED') AS days_with_gaps,

    MIN(day) AS earliest_day,
    MAX(day) AS latest_day
FROM raw.sms_daily_coverage;

-- ============================================================================
-- Function: raw.classify_and_record_sms
-- Purpose: Classify an SMS and record it in sms_classifications
-- ============================================================================
CREATE OR REPLACE FUNCTION raw.classify_and_record_sms(
    p_message_id VARCHAR,
    p_sender VARCHAR,
    p_received_at TIMESTAMPTZ,
    p_canonical_intent VARCHAR,
    p_legacy_intent VARCHAR DEFAULT NULL,
    p_pattern_name VARCHAR DEFAULT NULL,
    p_confidence NUMERIC DEFAULT 0.00,
    p_amount NUMERIC DEFAULT NULL,
    p_currency VARCHAR DEFAULT NULL,
    p_merchant VARCHAR DEFAULT NULL
) RETURNS BIGINT AS $$
DECLARE
    v_id BIGINT;
BEGIN
    INSERT INTO raw.sms_classifications (
        message_id, sender, received_at,
        canonical_intent, legacy_intent, pattern_name, confidence,
        amount, currency, merchant
    ) VALUES (
        p_message_id, p_sender, p_received_at,
        p_canonical_intent, p_legacy_intent, p_pattern_name, p_confidence,
        p_amount, p_currency, p_merchant
    )
    ON CONFLICT (message_id) DO UPDATE SET
        canonical_intent = EXCLUDED.canonical_intent,
        legacy_intent = EXCLUDED.legacy_intent,
        pattern_name = EXCLUDED.pattern_name,
        confidence = EXCLUDED.confidence,
        amount = EXCLUDED.amount,
        currency = EXCLUDED.currency,
        merchant = EXCLUDED.merchant,
        classified_at = NOW()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Function: raw.mark_sms_transaction_created
-- Purpose: Mark that an SMS classification resulted in a transaction
-- ============================================================================
CREATE OR REPLACE FUNCTION raw.mark_sms_transaction_created(
    p_message_id VARCHAR,
    p_transaction_id INTEGER
) RETURNS BOOLEAN AS $$
BEGIN
    UPDATE raw.sms_classifications
    SET created_transaction = TRUE,
        transaction_id = p_transaction_id
    WHERE message_id = p_message_id;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- View: raw.sms_intent_breakdown
-- Purpose: Show message counts by intent for verification
-- ============================================================================
CREATE OR REPLACE VIEW raw.sms_intent_breakdown AS
SELECT
    canonical_intent,
    COUNT(*) AS message_count,
    COUNT(*) FILTER (WHERE created_transaction) AS created_tx_count,
    ROUND(AVG(confidence), 2) AS avg_confidence,
    MIN(received_at) AS earliest,
    MAX(received_at) AS latest
FROM raw.sms_classifications
GROUP BY canonical_intent
ORDER BY message_count DESC;
