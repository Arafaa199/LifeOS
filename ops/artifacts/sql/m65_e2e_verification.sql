-- M6.5 E2E Test Verification Queries
-- Purpose: Verify raw_events + transactions integrity after webhook tests
-- Date: 2026-01-25

-- ============================================================================
-- Q1: Raw Events Status Distribution
-- ============================================================================
SELECT
    validation_status,
    COUNT(*) AS count,
    ROUND(AVG(parsed_amount)::NUMERIC, 2) AS avg_amount
FROM finance.raw_events
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY validation_status
ORDER BY count DESC;

-- ============================================================================
-- Q2: Recent Raw Events with Transaction Links
-- ============================================================================
SELECT
    re.id AS raw_event_id,
    re.event_type,
    re.client_id,
    re.validation_status,
    re.parsed_amount,
    re.parsed_currency,
    re.related_transaction_id,
    t.merchant_name AS tx_merchant,
    t.amount AS tx_amount,
    re.created_at
FROM finance.raw_events re
LEFT JOIN finance.transactions t ON t.id = re.related_transaction_id
WHERE re.created_at > NOW() - INTERVAL '24 hours'
ORDER BY re.created_at DESC
LIMIT 20;

-- ============================================================================
-- Q3: Idempotency Check - Duplicate Client IDs
-- ============================================================================
SELECT
    client_id,
    COUNT(*) AS event_count,
    COUNT(*) FILTER (WHERE validation_status = 'valid') AS valid_count,
    COUNT(*) FILTER (WHERE validation_status = 'duplicate') AS duplicate_count,
    COUNT(*) FILTER (WHERE validation_status = 'invalid') AS invalid_count
FROM finance.raw_events
WHERE client_id IS NOT NULL
GROUP BY client_id
HAVING COUNT(*) > 1
ORDER BY event_count DESC
LIMIT 10;

-- ============================================================================
-- Q4: Transaction Integrity - No Orphans
-- ============================================================================
-- Check: Every transaction with client_id should have at least one raw_event
SELECT
    t.id,
    t.client_id,
    t.merchant_name,
    t.amount,
    t.date,
    re.id AS raw_event_id,
    re.validation_status
FROM finance.transactions t
LEFT JOIN finance.raw_events re ON re.related_transaction_id = t.id
WHERE t.client_id IS NOT NULL
  AND t.created_at > NOW() - INTERVAL '24 hours'
ORDER BY t.created_at DESC;

-- ============================================================================
-- Q5: Validation Error Analysis
-- ============================================================================
SELECT
    id,
    client_id,
    validation_status,
    validation_errors,
    raw_payload->>'amount' AS payload_amount,
    raw_payload->>'raw_text' AS payload_raw_text,
    created_at
FROM finance.raw_events
WHERE validation_status = 'invalid'
  AND created_at > NOW() - INTERVAL '7 days'
ORDER BY created_at DESC
LIMIT 10;

-- ============================================================================
-- Q6: E2E Test Summary (for test harness verification)
-- ============================================================================
SELECT
    COUNT(*) FILTER (WHERE validation_status = 'valid') AS valid_events,
    COUNT(*) FILTER (WHERE validation_status = 'duplicate') AS duplicate_events,
    COUNT(*) FILTER (WHERE validation_status = 'invalid') AS invalid_events,
    COUNT(*) FILTER (WHERE validation_status = 'pending') AS pending_events,
    COUNT(*) AS total_events,
    COUNT(DISTINCT client_id) AS unique_clients,
    COUNT(DISTINCT related_transaction_id) FILTER (WHERE related_transaction_id IS NOT NULL) AS linked_transactions
FROM finance.raw_events
WHERE created_at > NOW() - INTERVAL '24 hours';

-- ============================================================================
-- Q7: Replay Idempotency Test
-- Expected: Same client_id submitted twice should show 1 valid + 1 duplicate
-- ============================================================================
WITH test_data AS (
    SELECT
        client_id,
        MIN(CASE WHEN validation_status = 'valid' THEN created_at END) AS first_valid,
        MIN(CASE WHEN validation_status = 'duplicate' THEN created_at END) AS first_duplicate,
        COUNT(*) FILTER (WHERE validation_status = 'valid') AS valid_count,
        COUNT(*) FILTER (WHERE validation_status = 'duplicate') AS duplicate_count
    FROM finance.raw_events
    WHERE client_id IS NOT NULL
    GROUP BY client_id
)
SELECT
    client_id,
    valid_count,
    duplicate_count,
    CASE
        WHEN valid_count = 1 AND duplicate_count >= 1 THEN 'IDEMPOTENT_OK'
        WHEN valid_count = 1 AND duplicate_count = 0 THEN 'SINGLE_SUBMIT'
        WHEN valid_count > 1 THEN 'IDEMPOTENCY_VIOLATION'
        ELSE 'UNKNOWN'
    END AS idempotency_status
FROM test_data
WHERE valid_count > 0 OR duplicate_count > 0
ORDER BY (valid_count + duplicate_count) DESC
LIMIT 20;
