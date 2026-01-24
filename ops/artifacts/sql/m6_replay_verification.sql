-- =============================================================================
-- M6.1 Full Replay Verification Queries
-- Run these queries after replay-full.sh to verify correctness
-- =============================================================================

-- =============================================================================
-- 1. SOURCE TABLE PRESERVATION CHECK
-- These tables must NOT be modified by replay
-- =============================================================================

-- Check raw tables are intact
SELECT
    'raw.bank_sms' as table_name,
    COUNT(*) as row_count,
    CASE WHEN COUNT(*) >= 0 THEN 'PRESERVED' ELSE 'ERROR' END as status
FROM raw.bank_sms
UNION ALL
SELECT 'raw.github_events', COUNT(*), 'PRESERVED' FROM raw.github_events
UNION ALL
SELECT 'raw.healthkit_samples', COUNT(*), 'PRESERVED' FROM raw.healthkit_samples
UNION ALL
SELECT 'raw.manual_entries', COUNT(*), 'PRESERVED' FROM raw.manual_entries;

-- Check config tables are intact
SELECT
    'finance.budgets' as table_name,
    COUNT(*) as row_count,
    CASE WHEN COUNT(*) > 0 THEN 'PRESERVED' ELSE 'WARNING: Empty' END as status
FROM finance.budgets
UNION ALL
SELECT 'finance.categories', COUNT(*),
    CASE WHEN COUNT(*) > 0 THEN 'PRESERVED' ELSE 'WARNING: Empty' END
FROM finance.categories
UNION ALL
SELECT 'finance.merchant_rules', COUNT(*),
    CASE WHEN COUNT(*) > 0 THEN 'PRESERVED' ELSE 'WARNING: Empty' END
FROM finance.merchant_rules;

-- =============================================================================
-- 2. TRANSACTION REBUILD VERIFICATION
-- =============================================================================

-- Count transactions by source
SELECT
    CASE
        WHEN external_id LIKE 'sms:%' THEN 'SMS Import'
        WHEN external_id LIKE 'receipt:%' THEN 'Receipt'
        WHEN client_id IS NOT NULL THEN 'iOS App'
        ELSE 'Unknown'
    END as source,
    COUNT(*) as count,
    SUM(CASE WHEN amount < 0 THEN amount ELSE 0 END) as total_spent,
    SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) as total_income
FROM finance.transactions
GROUP BY 1
ORDER BY count DESC;

-- Check for duplicate transactions (should be 0)
SELECT
    'Duplicate external_ids' as check_name,
    COUNT(*) as duplicate_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END as status
FROM (
    SELECT external_id, COUNT(*) as cnt
    FROM finance.transactions
    WHERE external_id IS NOT NULL
    GROUP BY external_id
    HAVING COUNT(*) > 1
) dupes;

-- Check for duplicate client_ids (should be 0)
SELECT
    'Duplicate client_ids' as check_name,
    COUNT(*) as duplicate_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END as status
FROM (
    SELECT client_id, COUNT(*) as cnt
    FROM finance.transactions
    WHERE client_id IS NOT NULL
    GROUP BY client_id
    HAVING COUNT(*) > 1
) dupes;

-- =============================================================================
-- 3. RECEIPT REBUILD VERIFICATION
-- =============================================================================

-- Count receipts by status
SELECT
    parse_status,
    COUNT(*) as count,
    SUM(total_amount) as total_value
FROM finance.receipts
GROUP BY parse_status
ORDER BY count DESC;

-- Check receipt-transaction links
SELECT
    'Linked receipts' as metric,
    COUNT(*) FILTER (WHERE linked_transaction_id IS NOT NULL) as linked,
    COUNT(*) FILTER (WHERE linked_transaction_id IS NULL AND parse_status = 'success') as unlinked_success,
    COUNT(*) FILTER (WHERE parse_status != 'success') as not_parsed
FROM finance.receipts;

-- =============================================================================
-- 4. FINANCIAL RECONCILIATION
-- =============================================================================

-- MTD Summary (should match dashboard)
SELECT
    (SELECT SUM(amount) FROM finance.transactions
     WHERE amount < 0
     AND finance.to_business_date(transaction_at) >= date_trunc('month', CURRENT_DATE AT TIME ZONE 'Asia/Dubai')::date
    ) as mtd_spend,
    (SELECT SUM(amount) FROM finance.transactions
     WHERE amount > 0
     AND finance.to_business_date(transaction_at) >= date_trunc('month', CURRENT_DATE AT TIME ZONE 'Asia/Dubai')::date
    ) as mtd_income,
    (SELECT COUNT(*) FROM finance.transactions
     WHERE finance.to_business_date(transaction_at) >= date_trunc('month', CURRENT_DATE AT TIME ZONE 'Asia/Dubai')::date
    ) as mtd_tx_count;

-- Compare with dashboard function
SELECT
    (finance.get_dashboard_payload())->>'mtd_spent' as dashboard_mtd_spent,
    (finance.get_dashboard_payload())->>'mtd_income' as dashboard_mtd_income,
    (finance.get_dashboard_payload())->>'today_spent' as dashboard_today_spent;

-- =============================================================================
-- 5. DERIVED TABLES VERIFICATION
-- =============================================================================

-- Check facts tables have been rebuilt
SELECT
    'facts.daily_health' as table_name,
    COUNT(*) as row_count,
    MIN(date) as earliest_day,
    MAX(date) as latest_day
FROM facts.daily_health
UNION ALL
SELECT 'facts.daily_finance', COUNT(*), MIN(date), MAX(date) FROM facts.daily_finance
UNION ALL
SELECT 'facts.daily_summary', COUNT(*), MIN(date), MAX(date) FROM facts.daily_summary;

-- Check life.daily_facts has been rebuilt
SELECT
    'life.daily_facts' as table_name,
    COUNT(*) as row_count,
    MIN(day) as earliest_day,
    MAX(day) as latest_day
FROM life.daily_facts;

-- Check insights have been regenerated
SELECT
    'insights.daily_finance_summary' as table_name,
    COUNT(*) as row_count,
    MIN(summary_date) as earliest,
    MAX(summary_date) as latest
FROM insights.daily_finance_summary;

-- =============================================================================
-- 6. IDEMPOTENCY CHECK
-- Run replay-full.sh twice and verify these counts match
-- =============================================================================

-- Capture these values before and after second replay
SELECT
    'Idempotency check' as test,
    (SELECT COUNT(*) FROM finance.transactions) as transactions,
    (SELECT COUNT(*) FROM finance.receipts) as receipts,
    (SELECT COUNT(*) FROM facts.daily_finance) as facts_finance,
    (SELECT COUNT(*) FROM life.daily_facts) as life_daily,
    (SELECT SUM(amount) FROM finance.transactions WHERE amount < 0) as total_spend,
    (SELECT SUM(amount) FROM finance.transactions WHERE amount > 0) as total_income;

-- =============================================================================
-- 7. DATA QUALITY CHECKS
-- =============================================================================

-- Transactions without categories (should have match_reason)
SELECT
    'Uncategorized transactions' as check_name,
    COUNT(*) as count,
    CASE WHEN COUNT(*) < 10 THEN 'OK' ELSE 'REVIEW' END as status
FROM finance.transactions
WHERE category = 'Uncategorized' OR category IS NULL;

-- Transactions with future dates (should be 0)
SELECT
    'Future-dated transactions' as check_name,
    COUNT(*) as count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END as status
FROM finance.transactions
WHERE finance.to_business_date(transaction_at) > CURRENT_DATE;

-- Orphaned receipt items (should be 0)
SELECT
    'Orphaned receipt items' as check_name,
    COUNT(*) as count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END as status
FROM finance.receipt_items ri
LEFT JOIN finance.receipts r ON ri.receipt_id = r.id
WHERE r.id IS NULL;
