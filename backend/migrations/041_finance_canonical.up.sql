-- Migration: 041_finance_canonical.up.sql
-- Purpose: Create canonical finance layer with correct amounts, signs, and directions
-- Date: 2026-01-24
--
-- FIXES:
-- 1. Uses `date` column (actual transaction date) instead of buggy `transaction_at`
-- 2. Properly excludes non-spending categories (Transfer, ATM, Credit Card Payment)
-- 3. Separates income vs expense directions
-- 4. Handles currencies properly (base currency = AED)
-- 5. Identifies refunds correctly

-- ============================================================================
-- VIEW: finance.canonical_transactions
-- Purpose: Normalize all transactions with correct direction, amounts, and flags
-- ============================================================================
CREATE OR REPLACE VIEW finance.canonical_transactions AS
SELECT
    id AS transaction_id,

    -- Use `date` column as the canonical date (transaction_at is buggy - set to import time)
    date AS transaction_date,

    -- Keep original transaction_at for reference but note it's import time
    transaction_at AS imported_at,

    client_id,
    external_id,

    -- Source detection
    CASE
        WHEN external_id LIKE 'sms:%' THEN 'sms'
        WHEN external_id LIKE 'receipt:%' THEN 'receipt'
        WHEN client_id IS NOT NULL THEN 'manual'
        ELSE 'unknown'
    END AS source,

    category,
    merchant_name_clean AS merchant,

    -- Original amount (preserves sign from raw data)
    amount AS original_amount,
    currency,

    -- Direction: income if positive OR income-type category
    CASE
        WHEN category IN ('Income', 'Salary', 'Deposit', 'Refund') THEN 'income'
        WHEN amount > 0 THEN 'income'
        ELSE 'expense'
    END AS direction,

    -- Canonical amount: always positive
    ABS(amount) AS canonical_amount,

    -- Refund detection: expense with positive amount, or Refund category
    CASE
        WHEN category = 'Refund' THEN TRUE
        WHEN amount > 0 AND category NOT IN ('Income', 'Salary', 'Deposit') THEN TRUE
        ELSE FALSE
    END AS is_refund,

    -- Base currency flag
    CASE WHEN UPPER(currency) = 'AED' THEN TRUE ELSE FALSE END AS is_base_currency,

    -- Exclude from spend totals: these are not actual spending
    CASE
        WHEN category IN ('Transfer', 'ATM', 'Credit Card Payment') THEN TRUE
        WHEN is_quarantined THEN TRUE
        ELSE FALSE
    END AS exclude_from_totals,

    -- Metadata
    is_quarantined,
    quarantine_reason,
    match_confidence,
    created_at

FROM finance.transactions
WHERE NOT COALESCE(is_hidden, FALSE);

COMMENT ON VIEW finance.canonical_transactions IS
'Canonical view of transactions with normalized direction, amounts, and exclusions.
Uses `date` column for transaction date (not buggy transaction_at).
Excludes Transfer, ATM, Credit Card Payment from spend totals.';

-- ============================================================================
-- VIEW: finance.daily_totals_aed
-- Purpose: Daily income and expense totals in AED only
-- ============================================================================
CREATE OR REPLACE VIEW finance.daily_totals_aed AS
SELECT
    transaction_date AS day,

    -- Income: sum of all income transactions in AED
    COALESCE(SUM(CASE
        WHEN direction = 'income' AND is_base_currency
        THEN canonical_amount
        ELSE 0
    END), 0) AS income_aed,

    -- Expense: sum of all expense transactions in AED (excluding transfers, ATM, CC payments)
    COALESCE(SUM(CASE
        WHEN direction = 'expense' AND is_base_currency AND NOT exclude_from_totals
        THEN canonical_amount
        ELSE 0
    END), 0) AS expense_aed,

    -- Net = income - expense (positive = net gain)
    COALESCE(SUM(CASE
        WHEN direction = 'income' AND is_base_currency THEN canonical_amount
        WHEN direction = 'expense' AND is_base_currency AND NOT exclude_from_totals THEN -canonical_amount
        ELSE 0
    END), 0) AS net_aed,

    -- Counts
    COUNT(*) FILTER (WHERE is_base_currency AND NOT exclude_from_totals) AS transaction_count,
    COUNT(*) FILTER (WHERE NOT is_base_currency) AS excluded_non_aed,
    COUNT(*) FILTER (WHERE exclude_from_totals) AS excluded_transfers,

    -- Refunds
    COALESCE(SUM(CASE
        WHEN is_refund AND is_base_currency
        THEN canonical_amount
        ELSE 0
    END), 0) AS refunds_aed,
    COUNT(*) FILTER (WHERE is_refund AND is_base_currency) AS refund_count

FROM finance.canonical_transactions
WHERE transaction_date IS NOT NULL
GROUP BY transaction_date
ORDER BY transaction_date DESC;

COMMENT ON VIEW finance.daily_totals_aed IS
'Daily income/expense totals in AED only.
Excludes: Transfer, ATM, Credit Card Payment, non-AED currencies.
Expense values are always POSITIVE (not negative).';

-- ============================================================================
-- VIEW: finance.canonical_summary
-- Purpose: Sanity check summary of the canonical layer
-- ============================================================================
CREATE OR REPLACE VIEW finance.canonical_summary AS
WITH stats AS (
    SELECT
        COUNT(*) AS total_transactions,
        COUNT(*) FILTER (WHERE is_base_currency) AS aed_transactions,
        COUNT(*) FILTER (WHERE NOT is_base_currency) AS non_aed_transactions,
        COUNT(*) FILTER (WHERE exclude_from_totals) AS excluded_transactions,
        COUNT(*) FILTER (WHERE direction = 'income') AS income_count,
        COUNT(*) FILTER (WHERE direction = 'expense') AS expense_count,
        COUNT(*) FILTER (WHERE is_refund) AS refund_count,

        -- AED totals
        SUM(CASE WHEN direction = 'income' AND is_base_currency THEN canonical_amount ELSE 0 END) AS total_income_aed,
        SUM(CASE WHEN direction = 'expense' AND is_base_currency AND NOT exclude_from_totals THEN canonical_amount ELSE 0 END) AS total_expense_aed,

        -- Non-AED totals (should be small)
        SUM(CASE WHEN NOT is_base_currency THEN canonical_amount ELSE 0 END) AS total_non_aed,

        -- Categories excluded
        COUNT(DISTINCT CASE WHEN exclude_from_totals THEN category END) AS excluded_category_count
    FROM finance.canonical_transactions
)
SELECT
    total_transactions,
    aed_transactions,
    non_aed_transactions,
    excluded_transactions,
    income_count,
    expense_count,
    refund_count,
    ROUND(total_income_aed, 2) AS total_income_aed,
    ROUND(total_expense_aed, 2) AS total_expense_aed,
    ROUND(total_income_aed - total_expense_aed, 2) AS net_aed,
    ROUND(total_non_aed, 2) AS total_non_aed_amount,
    excluded_category_count,
    CASE
        WHEN total_expense_aed > 0
        THEN ROUND(total_income_aed / total_expense_aed, 2)
        ELSE NULL
    END AS income_expense_ratio
FROM stats;

COMMENT ON VIEW finance.canonical_summary IS
'High-level summary of canonical transactions for sanity checking.';

-- ============================================================================
-- FUNCTION: finance.get_canonical_daily_totals(days_back)
-- Purpose: Get daily totals for last N days with formatting
-- ============================================================================
CREATE OR REPLACE FUNCTION finance.get_canonical_daily_totals(p_days_back INT DEFAULT 14)
RETURNS TABLE(
    day DATE,
    income_aed NUMERIC,
    expense_aed NUMERIC,
    net_aed NUMERIC,
    tx_count INT,
    is_weekend BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    WITH date_series AS (
        SELECT generate_series(
            CURRENT_DATE - p_days_back + 1,
            CURRENT_DATE,
            '1 day'::INTERVAL
        )::DATE AS day
    )
    SELECT
        d.day,
        COALESCE(t.income_aed, 0)::NUMERIC AS income_aed,
        COALESCE(t.expense_aed, 0)::NUMERIC AS expense_aed,
        COALESCE(t.net_aed, 0)::NUMERIC AS net_aed,
        COALESCE(t.transaction_count, 0)::INT AS tx_count,
        EXTRACT(DOW FROM d.day) IN (0, 5, 6) AS is_weekend  -- Friday, Saturday, Sunday (UAE weekend)
    FROM date_series d
    LEFT JOIN finance.daily_totals_aed t ON t.day = d.day
    ORDER BY d.day DESC;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION finance.get_canonical_daily_totals IS
'Returns daily totals for last N days, including days with no transactions.';
