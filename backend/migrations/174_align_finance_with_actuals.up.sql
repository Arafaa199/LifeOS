-- Migration 174: Align finance data with actual accounts and spending
-- Based on Financial_Tracker_2026.xlsx and user-provided balances as of Feb 8, 2026
--
-- Account balances:
--   Emirates NBD: 14,400.79 AED
--   Al Rajhi KSA: 320 SAR
--   Baseeta/Tasheel CC: 1639 SAR used / 2000 SAR limit
--   Tabby CC: 895 AED used / 1000 AED limit
--
-- Tabby installments:
--   2x 1244.14 AED (April & May) - Samsung 49" monitor
--   3x 872.03 AED (March, April, May) - Other purchase

BEGIN;

-- ============================================================================
-- 1. ADD CREDIT CARD ACCOUNTS
-- ============================================================================

INSERT INTO finance.accounts (name, institution, account_type, last_four, is_active, created_at)
VALUES
    ('Tabby Credit', 'Tabby', 'credit', NULL, true, NOW()),
    ('Baseeta Credit', 'Tasheel Finance', 'credit', NULL, true, NOW())
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 2. UPDATE RECURRING ITEMS TO MATCH ACTUAL EXPENSES
-- ============================================================================

-- Deactivate old/incorrect items
UPDATE finance.recurring_items SET is_active = false WHERE name IN (
    'Spotify', 'YouTube Premium', 'iCloud+', 'Car Insurance', 'Gym',
    'du Mobile', 'du Internet'
);

-- Update Claude Pro to correct amount (USD 200 = ~734 AED)
UPDATE finance.recurring_items
SET amount = 734, notes = 'USD 200/mo'
WHERE name = 'Claude Pro' AND is_active = true;

-- Update DEWA to winter rate
UPDATE finance.recurring_items
SET amount = 570, notes = 'Winter rate. Summer: 850'
WHERE name = 'DEWA' AND is_active = true;

-- Update Tabby repayment (will be recalculated based on installments)
UPDATE finance.recurring_items
SET is_active = false
WHERE name = 'Tabby Repayment';

-- Insert missing recurring items
INSERT INTO finance.recurring_items (name, amount, currency, type, cadence, day_of_month, is_active, notes, created_at)
VALUES
    -- Utilities
    ('Chiller (LOGIC UTILS)', 600, 'AED', 'expense', 'monthly', NULL, true, 'Was missing until audit', NOW()),
    ('e& Mobile', 316, 'AED', 'expense', 'monthly', 15, true, 'Jan bill was 494 (arrears)', NOW()),
    ('Du Mobile+Internet', 419, 'AED', 'expense', 'monthly', 18, true, 'Combined bill', NOW()),

    -- Subscriptions
    ('ChatGPT Plus', 77, 'AED', 'expense', 'monthly', 5, true, 'USD 21/mo', NOW()),
    ('Apple Subscriptions', 22, 'AED', 'expense', 'monthly', 15, true, 'iCloud+', NOW()),

    -- Living
    ('Protein Powder', 400, 'AED', 'expense', 'monthly', NULL, true, '520/bag, ~37 days supply', NOW()),
    ('Haircut (B27)', 350, 'AED', 'expense', 'monthly', NULL, true, 'B27 Barbershop', NOW()),
    ('Car Wash', 150, 'AED', 'expense', 'monthly', NULL, true, NULL, NOW()),
    ('Petrol', 500, 'AED', 'expense', 'monthly', NULL, true, 'Budget', NOW()),

    -- Temporary
    ('Zain KSA', 428, 'SAR', 'expense', 'monthly', NULL, true, 'Ends May 2026', NOW()),

    -- Rent (quarterly)
    ('Rent Q1 2026', 27000, 'AED', 'expense', 'quarterly', 22, true, 'Feb 22 payment', NOW())
ON CONFLICT DO NOTHING;

-- Update Tasheel loan if exists, or insert
UPDATE finance.recurring_items
SET amount = 1419, notes = 'Monthly installment'
WHERE name ILIKE '%tasheel%' AND is_active = true;

-- ============================================================================
-- 3. UPDATE/INSERT TABBY INSTALLMENTS
-- ============================================================================

-- Mark old installments as completed/inactive
UPDATE finance.installments
SET status = 'completed'
WHERE source = 'tabby'
  AND status = 'active'
  AND (final_due_date < '2026-01-01' OR final_due_date IS NULL);

-- Insert current Tabby installments
-- Samsung 49" Monitor: 4x 1244.14 AED (1 paid, 3 remaining: Feb, Mar, Apr... wait user said April & May)
-- Let me correct: 2 payments remaining (April & May) means 2 were already paid

INSERT INTO finance.installments (source, merchant, total_amount, currency, installments_total, installments_paid, installment_amount, purchase_date, next_due_date, final_due_date, status, notes, created_at, updated_at)
VALUES
    -- Samsung 49" Monitor: 4x 1244.14 = 4976.56 AED total
    -- 2 paid (Dec, Jan... or Jan, Feb), 2 remaining (Apr, May)
    ('tabby', 'Samsung 49" Monitor (Amazon.ae)', 4976.56, 'AED', 4, 2, 1244.14, '2025-12-12', '2026-04-12', '2026-05-12', 'active',
     '2 payments remaining: April & May 2026', NOW(), NOW()),

    -- Other purchase: 3x 872.03 = 2616.09 AED total
    -- 0 paid, 3 remaining (Mar, Apr, May)
    ('tabby', 'Smart Home Bundle', 2616.09, 'AED', 3, 0, 872.03, '2026-02-06', '2026-03-06', '2026-05-06', 'active',
     '3 payments: March, April, May 2026', NOW(), NOW())
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 4. CREATE/UPDATE FEB 2026 BUDGETS
-- ============================================================================

-- Delete existing Feb 2026 budgets if any
DELETE FROM finance.budgets WHERE month = '2026-02-01';

-- Insert Feb 2026 budgets based on Excel tracker
INSERT INTO finance.budgets (month, category, budget_amount, notes, created_at)
VALUES
    ('2026-02-01', 'Rent', 27000, 'Q1 rent due Feb 22', NOW()),
    ('2026-02-01', 'Groceries', 2700, 'Budget based on Jan actuals', NOW()),
    ('2026-02-01', 'Claude Pro', 734, 'USD 200/mo', NOW()),
    ('2026-02-01', 'Chiller', 600, 'LOGIC UTILS monthly', NOW()),
    ('2026-02-01', 'DEWA', 570, 'Winter rate', NOW()),
    ('2026-02-01', 'Petrol', 500, 'Monthly budget', NOW()),
    ('2026-02-01', 'Du', 419, 'Mobile + Internet', NOW()),
    ('2026-02-01', 'Protein', 400, 'Supplements', NOW()),
    ('2026-02-01', 'Haircut', 350, 'B27 Barbershop', NOW()),
    ('2026-02-01', 'e&', 316, 'Mobile', NOW()),
    ('2026-02-01', 'Car Wash', 150, NULL, NOW()),
    ('2026-02-01', 'ChatGPT', 77, 'USD 21/mo', NOW()),
    ('2026-02-01', 'Apple', 22, 'iCloud+', NOW()),
    ('2026-02-01', 'Zain KSA', 428, 'SAR - Ends May 2026', NOW()),
    ('2026-02-01', 'Tabby Payments', 2116, '1244.14 + 872.03 due this month', NOW()),
    ('2026-02-01', 'Food/Dining', 500, 'Eating out budget', NOW()),
    ('2026-02-01', 'Other', 500, 'Misc expenses', NOW());

-- ============================================================================
-- 5. FIX TRANSACTION CATEGORIES
-- ============================================================================

-- Categorize LOGIC UTILS as Utilities/Chiller
UPDATE finance.transactions
SET category = 'Utilities', notes = COALESCE(notes, '') || ' [Chiller]'
WHERE merchant_name ILIKE '%LOGIC UTIL%' AND category IS DISTINCT FROM 'Utilities';

-- Categorize Anthropic as Subscription
UPDATE finance.transactions
SET category = 'Subscription', notes = 'Claude API'
WHERE merchant_name ILIKE '%ANTHROPIC%' AND category = 'Uncategorized';

-- Categorize DHL as Shopping/Delivery
UPDATE finance.transactions
SET category = 'Shopping'
WHERE merchant_name ILIKE '%DHL%' AND category = 'Uncategorized';

-- Categorize Tasheel as Loan Payment
UPDATE finance.transactions
SET category = 'Loan Payment'
WHERE merchant_name ILIKE '%Tasheel%' AND category NOT IN ('Loan Payment');

-- Categorize SP MOUS as Shopping (Mous products)
UPDATE finance.transactions
SET category = 'Shopping', notes = 'Mous products'
WHERE merchant_name ILIKE '%MOUS%' AND category = 'Uncategorized';

COMMIT;
