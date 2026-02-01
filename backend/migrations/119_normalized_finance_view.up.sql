-- Migration 119: Normalized finance view
-- Creates a contract view over finance.transactions for the single-pipeline architecture.
-- Two-stage aggregation: per-category then per-day.
-- Sign conventions match life.refresh_daily_facts(): amount < 0 = expense, amount > 0 = income.
-- Filter: is_quarantined only (matching current life.refresh_daily_facts behavior).

CREATE OR REPLACE VIEW normalized.v_daily_finance AS
WITH daily_category AS (
    SELECT
        finance.to_business_date(transaction_at) AS date,
        COALESCE(category, 'Uncategorized') AS category,
        SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END) AS cat_spend,
        SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) AS cat_income,
        COUNT(*) AS cat_count
    FROM finance.transactions
    WHERE is_quarantined IS NOT TRUE
    GROUP BY finance.to_business_date(transaction_at), COALESCE(category, 'Uncategorized')
)
SELECT
    date,
    COALESCE(SUM(cat_spend), 0) AS spend_total,
    COALESCE(SUM(cat_income), 0) AS income_total,
    SUM(cat_count)::INT AS transaction_count,
    COALESCE(SUM(CASE WHEN category = 'Groceries' THEN cat_spend END), 0) AS spend_groceries,
    COALESCE(SUM(CASE WHEN category IN ('Dining', 'Restaurants', 'Food Delivery') THEN cat_spend END), 0) AS spend_restaurants,
    COALESCE(SUM(CASE WHEN category = 'Transport' THEN cat_spend END), 0) AS spend_transport,
    jsonb_object_agg(category, cat_spend) FILTER (WHERE cat_spend > 0) AS spending_by_category
FROM daily_category
GROUP BY date;

COMMENT ON VIEW normalized.v_daily_finance IS
'Normalized finance contract. Reads finance.transactions, aggregates per business date.
Sign: spend columns are positive (ABS of negative amounts). income_total is positive.
Filter: excludes is_quarantined. Does NOT filter is_hidden (matches life.refresh_daily_facts).
Canonical source for life.daily_facts finance columns.';
