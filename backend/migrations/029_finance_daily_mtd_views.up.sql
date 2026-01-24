-- Migration: 029_finance_daily_mtd_views
-- Purpose: Create canonical finance views for daily spending, daily income, and MTD summary
-- TASK: M1.1 - Finance Daily + MTD Views
-- Created: 2026-01-24

-- ============================================================================
-- 1. DAILY SPEND VIEW
-- Purpose: Spending per day aggregated by category
-- ============================================================================

CREATE OR REPLACE VIEW facts.daily_spend AS
SELECT
    finance.to_business_date(transaction_at) AS day,
    category,
    COUNT(*) AS transaction_count,
    SUM(ABS(amount)) AS total_spend,
    ROUND(AVG(ABS(amount)), 2) AS avg_transaction
FROM finance.transactions
WHERE amount < 0                      -- Expenses only (negative amounts)
  AND is_quarantined = false          -- Exclude quarantined
  AND category != 'Transfer'          -- Exclude transfers
GROUP BY finance.to_business_date(transaction_at), category
ORDER BY day DESC, total_spend DESC;

COMMENT ON VIEW facts.daily_spend IS
'Daily spending by category. Uses to_business_date() for Dubai timezone. Excludes quarantined and transfers.';


-- ============================================================================
-- 2. DAILY INCOME VIEW
-- Purpose: Income per day aggregated by source/category
-- ============================================================================

CREATE OR REPLACE VIEW facts.daily_income AS
SELECT
    finance.to_business_date(transaction_at) AS day,
    category,
    COUNT(*) AS transaction_count,
    SUM(amount) AS total_income,
    ROUND(AVG(amount), 2) AS avg_transaction
FROM finance.transactions
WHERE amount > 0                      -- Income only (positive amounts)
  AND is_quarantined = false          -- Exclude quarantined
GROUP BY finance.to_business_date(transaction_at), category
ORDER BY day DESC, total_income DESC;

COMMENT ON VIEW facts.daily_income IS
'Daily income by category. Uses to_business_date() for Dubai timezone. Excludes quarantined.';


-- ============================================================================
-- 3. MONTH TO DATE SUMMARY VIEW
-- Purpose: MTD totals for dashboard consumption
-- ============================================================================

CREATE OR REPLACE VIEW facts.month_to_date_summary AS
WITH current_month_bounds AS (
    SELECT
        DATE_TRUNC('month', CURRENT_DATE AT TIME ZONE 'Asia/Dubai')::DATE AS month_start,
        (DATE_TRUNC('month', CURRENT_DATE AT TIME ZONE 'Asia/Dubai') + INTERVAL '1 month' - INTERVAL '1 day')::DATE AS month_end
),
mtd_spend AS (
    SELECT
        COALESCE(SUM(ABS(amount)), 0) AS total_spend,
        COUNT(*) AS expense_count
    FROM finance.transactions, current_month_bounds cmb
    WHERE amount < 0
      AND is_quarantined = false
      AND category != 'Transfer'
      AND finance.to_business_date(transaction_at) >= cmb.month_start
      AND finance.to_business_date(transaction_at) <= CURRENT_DATE
),
mtd_income AS (
    SELECT
        COALESCE(SUM(amount), 0) AS total_income,
        COUNT(*) AS income_count
    FROM finance.transactions, current_month_bounds cmb
    WHERE amount > 0
      AND is_quarantined = false
      AND finance.to_business_date(transaction_at) >= cmb.month_start
      AND finance.to_business_date(transaction_at) <= CURRENT_DATE
),
spend_by_category AS (
    SELECT
        category,
        SUM(ABS(amount)) AS category_spend
    FROM finance.transactions, current_month_bounds cmb
    WHERE amount < 0
      AND is_quarantined = false
      AND category != 'Transfer'
      AND finance.to_business_date(transaction_at) >= cmb.month_start
      AND finance.to_business_date(transaction_at) <= CURRENT_DATE
    GROUP BY category
    ORDER BY category_spend DESC
),
today_spend AS (
    SELECT COALESCE(SUM(ABS(amount)), 0) AS today_total
    FROM finance.transactions
    WHERE amount < 0
      AND is_quarantined = false
      AND category != 'Transfer'
      AND finance.to_business_date(transaction_at) = CURRENT_DATE
)
SELECT
    -- Timeframe
    cmb.month_start,
    CURRENT_DATE AS as_of_date,

    -- Totals
    ms.total_spend AS mtd_spent,
    mi.total_income AS mtd_income,
    mi.total_income - ms.total_spend AS mtd_net,
    ts.today_total AS today_spent,

    -- Counts
    ms.expense_count,
    mi.income_count,

    -- Top category
    (SELECT category FROM spend_by_category LIMIT 1) AS top_category,
    (SELECT category_spend FROM spend_by_category LIMIT 1) AS top_category_spent,

    -- Category breakdown (as JSON)
    (SELECT COALESCE(
        jsonb_agg(jsonb_build_object(
            'category', category,
            'spent', category_spend
        ) ORDER BY category_spend DESC),
        '[]'::jsonb
    ) FROM spend_by_category) AS spend_by_category,

    -- Metadata
    CURRENT_TIMESTAMP AS generated_at

FROM current_month_bounds cmb
CROSS JOIN mtd_spend ms
CROSS JOIN mtd_income mi
CROSS JOIN today_spend ts;

COMMENT ON VIEW facts.month_to_date_summary IS
'Month-to-date summary: totals, net, top category, category breakdown. Dubai timezone.';


-- ============================================================================
-- 4. DAILY TOTALS VIEW (Convenience view for dashboard)
-- Purpose: Per-day totals combining spend and income
-- ============================================================================

CREATE OR REPLACE VIEW facts.daily_totals AS
WITH daily_data AS (
    SELECT
        finance.to_business_date(transaction_at) AS day,
        SUM(CASE WHEN amount < 0 AND category != 'Transfer' THEN ABS(amount) ELSE 0 END) AS total_spend,
        SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) AS total_income,
        COUNT(*) FILTER (WHERE amount < 0 AND category != 'Transfer') AS expense_count,
        COUNT(*) FILTER (WHERE amount > 0) AS income_count
    FROM finance.transactions
    WHERE is_quarantined = false
    GROUP BY finance.to_business_date(transaction_at)
)
SELECT
    day,
    total_spend,
    total_income,
    total_income - total_spend AS net,
    expense_count,
    income_count,
    expense_count + income_count AS total_count
FROM daily_data
ORDER BY day DESC;

COMMENT ON VIEW facts.daily_totals IS
'Daily totals: spend, income, net per day. Excludes quarantined and transfer expenses.';
