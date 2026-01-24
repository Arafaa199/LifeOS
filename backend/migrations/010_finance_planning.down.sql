-- Rollback Finance Planning Knowledge Schema

-- Drop views
DROP VIEW IF EXISTS finance.upcoming_recurring;
DROP VIEW IF EXISTS finance.budget_status;

-- Drop trigger
DROP TRIGGER IF EXISTS categorize_transaction_trigger ON finance.transactions;

-- Remove columns from transactions
ALTER TABLE finance.transactions
DROP COLUMN IF EXISTS match_rule_id,
DROP COLUMN IF EXISTS match_reason,
DROP COLUMN IF EXISTS match_confidence;

-- Remove columns from merchant_rules
ALTER TABLE finance.merchant_rules
DROP COLUMN IF EXISTS category_id,
DROP COLUMN IF EXISTS confidence,
DROP COLUMN IF EXISTS match_count,
DROP COLUMN IF EXISTS last_matched_at,
DROP COLUMN IF EXISTS is_active,
DROP COLUMN IF EXISTS notes;

-- Drop recurring_items table
DROP TABLE IF EXISTS finance.recurring_items;

-- Remove columns from budgets
ALTER TABLE finance.budgets
DROP COLUMN IF EXISTS category_id,
DROP COLUMN IF EXISTS notes,
DROP COLUMN IF EXISTS created_at,
DROP COLUMN IF EXISTS updated_at;

-- Drop categories table
DROP TABLE IF EXISTS finance.categories;

-- Recreate original trigger
CREATE OR REPLACE FUNCTION finance.categorize_transaction()
RETURNS TRIGGER AS $$
DECLARE
    v_rule RECORD;
    v_merchant_clean VARCHAR(200);
BEGIN
    v_merchant_clean := UPPER(COALESCE(NEW.merchant_name_clean, NEW.merchant_name, ''));

    IF NEW.category IS NOT NULL AND NEW.category != 'Uncategorized' AND NEW.category != '' THEN
        RETURN NEW;
    END IF;

    SELECT * INTO v_rule
    FROM finance.merchant_rules
    WHERE v_merchant_clean LIKE UPPER(merchant_pattern)
    ORDER BY priority DESC
    LIMIT 1;

    IF FOUND THEN
        NEW.category := v_rule.category;
        NEW.subcategory := v_rule.subcategory;
        NEW.is_grocery := COALESCE(v_rule.is_grocery, false);
        NEW.is_restaurant := COALESCE(v_rule.is_restaurant, false);
        NEW.is_food_related := COALESCE(v_rule.is_food_related, false);
        NEW.store_name := v_rule.store_name;
    ELSE
        IF NEW.category IS NULL OR NEW.category = '' THEN
            NEW.category := 'Uncategorized';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER categorize_transaction_trigger
    BEFORE INSERT OR UPDATE OF merchant_name_clean ON finance.transactions
    FOR EACH ROW EXECUTE FUNCTION finance.categorize_transaction();
