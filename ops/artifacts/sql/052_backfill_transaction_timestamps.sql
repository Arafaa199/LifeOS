-- Migration 052: Backfill transaction_at from SMS received_at
-- Purpose: Fix transactions imported with import timestamp instead of SMS timestamp
-- Created: 2026-01-24
--
-- Issue: import-sms-transactions.js was setting transaction_at to NOW()
-- instead of the SMS received_at timestamp.
--
-- Guard: Only updates transactions where transaction_at is on 2026-01-24 (bulk import date)
-- and sms_classifications has a different received_at date.

BEGIN;

-- Show before state
SELECT 'BEFORE: Transactions by transaction_at date' as step;
SELECT
    (transaction_at AT TIME ZONE 'Asia/Dubai')::date as tx_date,
    COUNT(*) as count
FROM finance.transactions
WHERE external_id LIKE 'sms:%'
GROUP BY 1
ORDER BY 1 DESC
LIMIT 10;

-- Backfill transaction_at from sms_classifications.received_at
-- Guard: Only touch transactions from 2026-01-24 bulk import
UPDATE finance.transactions t
SET
    transaction_at = sc.received_at,
    date = finance.to_business_date(sc.received_at)
FROM raw.sms_classifications sc
WHERE sc.transaction_id = t.id
  AND t.external_id LIKE 'sms:%'
  AND (t.transaction_at AT TIME ZONE 'Asia/Dubai')::date = '2026-01-24'::date
  AND (sc.received_at AT TIME ZONE 'Asia/Dubai')::date != '2026-01-24'::date;

-- Show after state
SELECT 'AFTER: Transactions by transaction_at date' as step;
SELECT
    (transaction_at AT TIME ZONE 'Asia/Dubai')::date as tx_date,
    COUNT(*) as count
FROM finance.transactions
WHERE external_id LIKE 'sms:%'
GROUP BY 1
ORDER BY 1 DESC
LIMIT 15;

-- Verify date derivation is correct
SELECT 'VERIFICATION: Sample rows with both timestamps' as step;
SELECT
    t.id,
    t.transaction_at,
    t.date,
    finance.to_business_date(t.transaction_at) as derived_date,
    CASE WHEN t.date = finance.to_business_date(t.transaction_at)
         THEN 'OK' ELSE 'MISMATCH' END as check
FROM finance.transactions t
WHERE external_id LIKE 'sms:%'
ORDER BY t.transaction_at DESC
LIMIT 10;

COMMIT;
