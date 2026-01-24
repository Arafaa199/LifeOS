-- Migration: Finance Timeline View
-- Purpose: Create a unified timeline view that distinguishes bank transactions, refunds, and wallet-only events
-- Author: Claude Coder
-- Date: 2026-01-25

-- Drop view if exists (for idempotent reruns)
DROP VIEW IF EXISTS finance.v_timeline CASCADE;

-- Create timeline view
CREATE VIEW finance.v_timeline AS
WITH sms_events AS (
    -- SMS-sourced events with intent classification
    SELECT
        sc.received_at,
        sc.canonical_intent,
        sc.merchant,
        sc.amount,
        sc.currency,
        sc.transaction_id,
        sc.created_transaction,
        t.category,
        t.date as transaction_date
    FROM raw.sms_classifications sc
    LEFT JOIN finance.transactions t ON sc.transaction_id = t.id
),
transaction_events AS (
    -- All transactions with their source
    SELECT
        t.id as transaction_id,
        COALESCE(t.transaction_at, t.date::timestamptz) as event_time,
        t.date,
        t.merchant_name,
        t.amount,
        t.currency,
        t.category,
        CASE
            WHEN t.client_id IS NOT NULL THEN 'webhook'
            WHEN t.external_id LIKE 'SMS%' THEN 'sms'
            ELSE 'receipt'
        END as source
    FROM finance.transactions t
),
sms_only_events AS (
    -- SMS events that didn't create transactions (declined, info, etc.)
    SELECT
        se.received_at as event_time,
        NULL::date as date,
        se.merchant,
        se.amount,
        se.currency,
        NULL::varchar(50) as category,
        'sms' as source,
        se.canonical_intent,
        NULL::integer as transaction_id
    FROM sms_events se
    WHERE se.created_transaction = false
      AND se.canonical_intent IN ('FIN_TXN_DECLINED', 'FIN_INFO_ONLY', 'FIN_TXN_REFUND')
)
SELECT
    -- Unified timeline from transactions
    te.event_time,
    te.date,
    EXTRACT(HOUR FROM te.event_time AT TIME ZONE 'Asia/Dubai')::int || ':' ||
        LPAD(EXTRACT(MINUTE FROM te.event_time AT TIME ZONE 'Asia/Dubai')::text, 2, '0') as time,
    CASE
        -- Bank transactions (actual money movement)
        WHEN te.category IN ('Purchase', 'Food', 'Grocery', 'Transport', 'Shopping', 'Utilities', 'Health', 'ATM', 'Bank Fees')
             AND te.amount < 0 THEN 'bank_tx'
        WHEN te.category IN ('Income', 'Salary', 'Deposit')
             AND te.amount > 0 THEN 'bank_tx'
        -- Refunds (money returned to account)
        WHEN te.category = 'Refund' AND te.amount > 0 THEN 'refund'
        -- Transfers (internal movements, not spending)
        WHEN te.category IN ('Transfer', 'Credit Card Payment') THEN 'info'
        -- Default to bank transaction
        ELSE 'bank_tx'
    END as event_type,
    te.amount,
    te.currency,
    te.merchant_name as merchant,
    te.category,
    te.source,
    CASE
        -- Actionable: actual bank account movements
        WHEN te.category IN ('Purchase', 'Food', 'Grocery', 'Transport', 'Shopping', 'Utilities', 'Health', 'ATM', 'Bank Fees', 'Income', 'Salary', 'Deposit', 'Refund') THEN true
        -- Not actionable: transfers, internal movements
        WHEN te.category IN ('Transfer', 'Credit Card Payment') THEN false
        -- Default to actionable
        ELSE true
    END as is_actionable,
    te.transaction_id
FROM transaction_events te

UNION ALL

SELECT
    -- Wallet-only events (CAREEM, Amazon refunds that don't affect bank)
    so.event_time,
    so.date,
    EXTRACT(HOUR FROM so.event_time AT TIME ZONE 'Asia/Dubai')::int || ':' ||
        LPAD(EXTRACT(MINUTE FROM so.event_time AT TIME ZONE 'Asia/Dubai')::text, 2, '0') as time,
    CASE
        WHEN so.canonical_intent = 'FIN_TXN_DECLINED' THEN 'info'
        WHEN so.canonical_intent = 'FIN_TXN_REFUND' THEN 'wallet_event'
        WHEN so.canonical_intent = 'FIN_INFO_ONLY' THEN 'info'
        ELSE 'info'
    END as event_type,
    so.amount,
    so.currency,
    so.merchant,
    so.category,
    so.source,
    false as is_actionable,  -- Wallet events are informational only
    so.transaction_id
FROM sms_only_events so

ORDER BY event_time DESC;

-- Add comment
COMMENT ON VIEW finance.v_timeline IS 'Unified finance timeline distinguishing bank transactions, refunds, wallet events, and informational messages';
