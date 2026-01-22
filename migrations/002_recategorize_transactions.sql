-- Migration 002: Recategorize existing transactions using merchant rules
-- Run on nexus: psql -U nexus -d nexus -f migrations/002_recategorize_transactions.sql

BEGIN;

-- ============================================================================
-- STEP 1: Normalize merchant names
-- ============================================================================

-- Careem variants
UPDATE finance.transactions
SET merchant_name_clean = 'Careem'
WHERE UPPER(merchant_name) LIKE '%CAREEM%'
  AND UPPER(merchant_name) NOT LIKE '%CAREEM FOOD%'
  AND UPPER(merchant_name) NOT LIKE '%CAREEM QUIK%';

UPDATE finance.transactions
SET merchant_name_clean = 'Careem Food'
WHERE UPPER(merchant_name) LIKE '%CAREEM FOOD%';

UPDATE finance.transactions
SET merchant_name_clean = 'Careem Quik'
WHERE UPPER(merchant_name) LIKE '%CAREEM QUIK%';

-- Carrefour
UPDATE finance.transactions
SET merchant_name_clean = 'Carrefour'
WHERE UPPER(merchant_name) LIKE '%CARREFOUR%'
   OR LOWER(merchant_name) LIKE '%carrefouruae%';

-- Talabat
UPDATE finance.transactions
SET merchant_name_clean = 'Talabat'
WHERE UPPER(merchant_name) LIKE '%TALABAT%';

-- Lulu
UPDATE finance.transactions
SET merchant_name_clean = 'Lulu Hypermarket'
WHERE UPPER(merchant_name) LIKE '%LULU%';

-- Spinneys
UPDATE finance.transactions
SET merchant_name_clean = 'Spinneys'
WHERE UPPER(merchant_name) LIKE '%SPINNEYS%';

-- Amazon
UPDATE finance.transactions
SET merchant_name_clean = 'Amazon'
WHERE UPPER(merchant_name) LIKE '%AMAZON%';

-- Noon
UPDATE finance.transactions
SET merchant_name_clean = 'Noon'
WHERE UPPER(merchant_name) LIKE '%NOON%'
  AND UPPER(merchant_name) NOT LIKE '%NOON FOOD%'
  AND UPPER(merchant_name) NOT LIKE '%NOON MINUTES%';

-- Starbucks
UPDATE finance.transactions
SET merchant_name_clean = 'Starbucks'
WHERE UPPER(merchant_name) LIKE '%STARBUCKS%';

-- McDonald's
UPDATE finance.transactions
SET merchant_name_clean = 'McDonald''s'
WHERE UPPER(merchant_name) LIKE '%MCDONALD%';

-- Remove trailing spaces and normalize remaining
UPDATE finance.transactions
SET merchant_name_clean = TRIM(REGEXP_REPLACE(merchant_name_clean, '\s+', ' ', 'g'))
WHERE merchant_name_clean IS NOT NULL;

-- ============================================================================
-- STEP 2: Categorize large transfers (> 5000 AED/SAR) as Transfer
-- ============================================================================

UPDATE finance.transactions
SET category = 'Transfer',
    subcategory = 'Large Transfer'
WHERE ABS(amount) > 5000
  AND (category IS NULL OR category = 'Purchase' OR category = 'Other' OR category = '')
  AND merchant_name IS NULL;

-- Salary deposits
UPDATE finance.transactions
SET category = 'Income',
    subcategory = 'Salary'
WHERE UPPER(COALESCE(merchant_name, '')) LIKE '%SALARY%'
   OR (amount > 5000 AND category = 'Salary');

-- ============================================================================
-- STEP 3: Apply merchant rules to categorize transactions
-- ============================================================================

-- Create a function to apply rules (highest priority first)
CREATE OR REPLACE FUNCTION finance.apply_merchant_rules()
RETURNS INTEGER AS $$
DECLARE
    total_updated INTEGER := 0;
    rows_affected INTEGER;
    rule RECORD;
BEGIN
    -- Process rules in priority order (highest first)
    FOR rule IN
        SELECT * FROM finance.merchant_rules
        ORDER BY priority DESC, id
    LOOP
        -- Update transactions matching this pattern
        UPDATE finance.transactions t
        SET
            category = rule.category,
            subcategory = rule.subcategory,
            is_grocery = rule.is_grocery,
            is_restaurant = rule.is_restaurant,
            is_food_related = rule.is_food_related,
            store_name = COALESCE(rule.store_name, t.store_name)
        WHERE (UPPER(t.merchant_name) LIKE UPPER(rule.merchant_pattern)
               OR UPPER(t.merchant_name_clean) LIKE UPPER(rule.merchant_pattern))
          AND (t.category IS NULL
               OR t.category IN ('Purchase', 'Other', 'PoS', 'Online Purchase', 'ATM', ''));

        GET DIAGNOSTICS rows_affected = ROW_COUNT;
        total_updated := total_updated + rows_affected;
    END LOOP;

    RETURN total_updated;
END;
$$ LANGUAGE plpgsql;

-- Apply the rules
SELECT finance.apply_merchant_rules() as transactions_updated;

-- ============================================================================
-- STEP 4: Handle specific Careem categorization
-- ============================================================================

-- Careem Food -> Food category with is_restaurant=true
UPDATE finance.transactions
SET category = 'Food',
    subcategory = 'Delivery',
    is_restaurant = TRUE,
    is_food_related = TRUE
WHERE UPPER(merchant_name) LIKE '%CAREEM FOOD%';

-- Careem Quik (quick commerce, could be food or other) -> Transport for now
UPDATE finance.transactions
SET category = 'Transport',
    subcategory = 'Rideshare'
WHERE UPPER(merchant_name) LIKE '%CAREEM QUIK%';

-- Generic Careem -> Transport
UPDATE finance.transactions
SET category = 'Transport',
    subcategory = 'Rideshare'
WHERE UPPER(merchant_name) LIKE '%CAREEM%'
  AND category NOT IN ('Food', 'Transport')
  AND UPPER(merchant_name) NOT LIKE '%CAREEM FOOD%';

-- ============================================================================
-- STEP 5: Handle ATM withdrawals
-- ============================================================================

UPDATE finance.transactions
SET category = 'Cash',
    subcategory = 'ATM Withdrawal'
WHERE UPPER(COALESCE(merchant_name, '')) LIKE '%ATM%'
   OR category = 'ATM';

-- ============================================================================
-- STEP 6: Mark remaining uncategorized as 'Other' for manual review
-- ============================================================================

UPDATE finance.transactions
SET category = 'Uncategorized'
WHERE category IS NULL
   OR category = ''
   OR category IN ('Purchase', 'Online Purchase', 'PoS');

COMMIT;

-- ============================================================================
-- VERIFICATION: Show category distribution after migration
-- ============================================================================

SELECT
    category,
    COUNT(*) as tx_count,
    SUM(ABS(amount)) as total_amount,
    currency
FROM finance.transactions
GROUP BY category, currency
ORDER BY total_amount DESC;

-- Show remaining uncategorized transactions for review
SELECT
    merchant_name,
    merchant_name_clean,
    COUNT(*) as occurrences,
    SUM(ABS(amount)) as total_amount,
    currency
FROM finance.transactions
WHERE category = 'Uncategorized'
GROUP BY merchant_name, merchant_name_clean, currency
ORDER BY total_amount DESC
LIMIT 20;
