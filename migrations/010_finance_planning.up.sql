-- Finance Planning Knowledge Schema
-- Categories, Budgets, Recurring Items, Matching Rules

-- 1. Categories table - source of truth for category metadata
CREATE TABLE IF NOT EXISTS finance.categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    type VARCHAR(10) NOT NULL CHECK (type IN ('expense', 'income')),
    icon VARCHAR(50),
    color VARCHAR(20),
    keywords TEXT[], -- patterns for auto-matching
    is_active BOOLEAN DEFAULT true,
    display_order INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Seed default categories
INSERT INTO finance.categories (name, type, icon, keywords, display_order) VALUES
    ('Grocery', 'expense', 'cart.fill', ARRAY['carrefour', 'lulu', 'spinneys', 'choithrams', 'viva', 'union coop'], 1),
    ('Restaurant', 'expense', 'fork.knife', ARRAY['talabat', 'deliveroo', 'zomato', 'careem food', 'noon food'], 2),
    ('Transport', 'expense', 'car.fill', ARRAY['uber', 'careem', 'salik', 'rta', 'enoc', 'adnoc', 'emarat'], 3),
    ('Utilities', 'expense', 'bolt.fill', ARRAY['dewa', 'etisalat', 'du', 'addc'], 4),
    ('Entertainment', 'expense', 'tv.fill', ARRAY['netflix', 'spotify', 'apple', 'amazon prime', 'disney'], 5),
    ('Health', 'expense', 'heart.fill', ARRAY['pharmacy', 'hospital', 'clinic', 'doctor'], 6),
    ('Shopping', 'expense', 'bag.fill', ARRAY['amazon', 'noon', 'namshi', 'shein'], 7),
    ('Loan', 'expense', 'banknote.fill', ARRAY['tasheel', 'mashreq', 'adcb', 'fab'], 8),
    ('Subscription', 'expense', 'repeat', ARRAY['netflix', 'spotify', 'gym', 'membership'], 9),
    ('Other', 'expense', 'ellipsis.circle.fill', ARRAY[]::TEXT[], 99),
    ('Salary', 'income', 'banknote', ARRAY['salary', 'payroll', 'wage'], 1),
    ('Freelance', 'income', 'briefcase', ARRAY['freelance', 'consulting', 'contract'], 2),
    ('Investment', 'income', 'chart.line.uptrend.xyaxis', ARRAY['dividend', 'interest', 'return'], 3),
    ('Refund', 'income', 'arrow.uturn.backward', ARRAY['refund', 'cashback', 'return'], 4),
    ('Gift', 'income', 'gift', ARRAY['gift', 'bonus'], 5),
    ('Uncategorized', 'expense', 'questionmark.circle', ARRAY[]::TEXT[], 100)
ON CONFLICT (name) DO NOTHING;

-- 2. Enhanced budgets table (keep existing, add category reference)
ALTER TABLE finance.budgets
ADD COLUMN IF NOT EXISTS category_id INTEGER REFERENCES finance.categories(id),
ADD COLUMN IF NOT EXISTS notes TEXT,
ADD COLUMN IF NOT EXISTS created_at TIMESTAMP DEFAULT NOW(),
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT NOW();

-- Update existing budgets to link to categories
UPDATE finance.budgets b
SET category_id = c.id
FROM finance.categories c
WHERE LOWER(b.category) = LOWER(c.name)
AND b.category_id IS NULL;

-- 3. Recurring items table
CREATE TABLE IF NOT EXISTS finance.recurring_items (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    amount NUMERIC(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'AED',
    type VARCHAR(10) NOT NULL CHECK (type IN ('expense', 'income')),
    cadence VARCHAR(20) NOT NULL CHECK (cadence IN ('daily', 'weekly', 'biweekly', 'monthly', 'quarterly', 'yearly')),
    day_of_month INTEGER, -- for monthly (1-31)
    day_of_week INTEGER, -- for weekly (0-6, 0=Sunday)
    next_due_date DATE,
    last_occurrence DATE,
    category_id INTEGER REFERENCES finance.categories(id),
    merchant_pattern VARCHAR(200), -- for auto-matching transactions
    is_active BOOLEAN DEFAULT true,
    auto_create BOOLEAN DEFAULT false, -- auto-create transaction on due date
    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_recurring_items_next_due ON finance.recurring_items(next_due_date) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_recurring_items_category ON finance.recurring_items(category_id);

-- 4. Enhanced matching rules (add category_id reference)
ALTER TABLE finance.merchant_rules
ADD COLUMN IF NOT EXISTS category_id INTEGER REFERENCES finance.categories(id),
ADD COLUMN IF NOT EXISTS confidence INTEGER DEFAULT 100 CHECK (confidence BETWEEN 0 AND 100),
ADD COLUMN IF NOT EXISTS match_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS last_matched_at TIMESTAMP,
ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS notes TEXT;

-- Update existing rules to link to categories
UPDATE finance.merchant_rules r
SET category_id = c.id
FROM finance.categories c
WHERE LOWER(r.category) = LOWER(c.name)
AND r.category_id IS NULL;

-- 5. Add match tracking to transactions
ALTER TABLE finance.transactions
ADD COLUMN IF NOT EXISTS match_rule_id INTEGER REFERENCES finance.merchant_rules(id),
ADD COLUMN IF NOT EXISTS match_reason VARCHAR(100),
ADD COLUMN IF NOT EXISTS match_confidence INTEGER;

-- 6. Function to categorize transaction using rules
CREATE OR REPLACE FUNCTION finance.categorize_transaction()
RETURNS TRIGGER AS $$
DECLARE
    v_rule RECORD;
    v_category_name VARCHAR(50);
    v_merchant_clean VARCHAR(200);
BEGIN
    -- Clean merchant name
    v_merchant_clean := UPPER(COALESCE(NEW.merchant_name_clean, NEW.merchant_name, ''));

    -- Skip if already categorized (unless it's Uncategorized)
    IF NEW.category IS NOT NULL AND NEW.category != 'Uncategorized' AND NEW.category != '' THEN
        RETURN NEW;
    END IF;

    -- Find matching rule by priority (highest first)
    SELECT r.*, c.name as category_name
    INTO v_rule
    FROM finance.merchant_rules r
    LEFT JOIN finance.categories c ON c.id = r.category_id
    WHERE r.is_active = true
    AND v_merchant_clean LIKE UPPER(r.merchant_pattern)
    ORDER BY r.priority DESC, r.confidence DESC
    LIMIT 1;

    IF FOUND THEN
        -- Use category from rule (prefer category_id lookup, fallback to string)
        NEW.category := COALESCE(v_rule.category_name, v_rule.category);
        NEW.subcategory := v_rule.subcategory;
        NEW.is_grocery := COALESCE(v_rule.is_grocery, false);
        NEW.is_restaurant := COALESCE(v_rule.is_restaurant, false);
        NEW.is_food_related := COALESCE(v_rule.is_food_related, false);
        NEW.store_name := v_rule.store_name;
        NEW.match_rule_id := v_rule.id;
        NEW.match_reason := 'rule:' || v_rule.id;
        NEW.match_confidence := v_rule.confidence;

        -- Update rule match stats
        UPDATE finance.merchant_rules
        SET match_count = match_count + 1,
            last_matched_at = NOW()
        WHERE id = v_rule.id;
    ELSE
        -- No match - set as Uncategorized
        IF NEW.category IS NULL OR NEW.category = '' THEN
            NEW.category := 'Uncategorized';
            NEW.match_reason := 'no_match';
            NEW.match_confidence := 0;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Recreate trigger (drop first to avoid duplicate)
DROP TRIGGER IF EXISTS categorize_transaction_trigger ON finance.transactions;
CREATE TRIGGER categorize_transaction_trigger
    BEFORE INSERT OR UPDATE OF merchant_name_clean ON finance.transactions
    FOR EACH ROW EXECUTE FUNCTION finance.categorize_transaction();

-- 7. View for budget status with category details
CREATE OR REPLACE VIEW finance.budget_status AS
SELECT
    b.id,
    b.month,
    b.category,
    c.id as category_id,
    c.type as category_type,
    c.icon as category_icon,
    b.budget_amount,
    COALESCE(spent.total, 0) as spent,
    b.budget_amount - COALESCE(spent.total, 0) as remaining,
    CASE
        WHEN COALESCE(spent.total, 0) > b.budget_amount THEN 'over'
        WHEN COALESCE(spent.total, 0) > b.budget_amount * 0.8 THEN 'warning'
        ELSE 'ok'
    END as status
FROM finance.budgets b
LEFT JOIN finance.categories c ON c.id = b.category_id OR LOWER(c.name) = LOWER(b.category)
LEFT JOIN LATERAL (
    SELECT ABS(SUM(t.amount)) as total
    FROM finance.transactions t
    WHERE t.amount < 0
    AND LOWER(t.category) = LOWER(b.category)
    AND DATE_TRUNC('month', t.date) = DATE_TRUNC('month', b.month)
    AND NOT t.is_quarantined
) spent ON true;

-- 8. View for upcoming recurring items
CREATE OR REPLACE VIEW finance.upcoming_recurring AS
SELECT
    r.*,
    c.name as category_name,
    c.icon as category_icon,
    r.next_due_date - CURRENT_DATE as days_until_due
FROM finance.recurring_items r
LEFT JOIN finance.categories c ON c.id = r.category_id
WHERE r.is_active = true
AND r.next_due_date >= CURRENT_DATE
ORDER BY r.next_due_date;
