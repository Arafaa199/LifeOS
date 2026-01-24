-- =============================================================================
-- Performance Indexes for Nexus Database
-- Adds composite indexes for common query patterns
-- =============================================================================

-- Composite index for date + category queries (dashboard, monthly summaries)
CREATE INDEX IF NOT EXISTS idx_transactions_date_category
ON finance.transactions(date DESC, category);

-- Composite index for merchant history with date sorting
CREATE INDEX IF NOT EXISTS idx_transactions_merchant_date
ON finance.transactions(merchant_name, date DESC);

-- Composite index for category + amount (budget tracking)
CREATE INDEX IF NOT EXISTS idx_transactions_category_amount
ON finance.transactions(category, amount) WHERE amount < 0;

-- Partial index for expenses only (most common query)
CREATE INDEX IF NOT EXISTS idx_transactions_expenses_date
ON finance.transactions(date DESC, amount) WHERE amount < 0;

-- Partial index for income only
CREATE INDEX IF NOT EXISTS idx_transactions_income_date
ON finance.transactions(date DESC, amount) WHERE amount > 0;

-- Index for food-related transactions (nutrition integration)
CREATE INDEX IF NOT EXISTS idx_transactions_food_date
ON finance.transactions(date DESC) WHERE is_food_related = true;

-- Verify indexes
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_indexes
JOIN pg_class ON pg_class.relname = indexname
WHERE schemaname = 'finance'
ORDER BY pg_relation_size(indexrelid) DESC;
