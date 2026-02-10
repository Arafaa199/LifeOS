-- Migration 176: Financial position tracking
-- Adds account balances, unified upcoming payments view, and auto-reconciliation

BEGIN;

-- ============================================================================
-- 1. ACCOUNT BALANCES TABLE (track point-in-time balances)
-- ============================================================================

CREATE TABLE IF NOT EXISTS finance.account_balances (
    id SERIAL PRIMARY KEY,
    account_id INT NOT NULL REFERENCES finance.accounts(id),
    balance NUMERIC(12,2) NOT NULL,
    balance_date DATE NOT NULL DEFAULT CURRENT_DATE,
    currency VARCHAR(3) NOT NULL DEFAULT 'AED',
    is_liability BOOLEAN NOT NULL DEFAULT false,  -- true for credit cards (balance = amount owed)
    credit_limit NUMERIC(12,2),  -- for credit accounts
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(account_id, balance_date)
);

-- Insert current balances based on user-provided data (Feb 8, 2026)
INSERT INTO finance.account_balances (account_id, balance, balance_date, currency, is_liability, credit_limit, notes)
SELECT id, 14400.79, '2026-02-08', 'AED', false, NULL, 'User reported balance'
FROM finance.accounts WHERE name = 'EmiratesNBD Debit'
ON CONFLICT DO NOTHING;

INSERT INTO finance.account_balances (account_id, balance, balance_date, currency, is_liability, credit_limit, notes)
SELECT id, 320.00, '2026-02-08', 'SAR', false, NULL, 'User reported balance'
FROM finance.accounts WHERE name = 'AlRajhi Debit'
ON CONFLICT DO NOTHING;

INSERT INTO finance.account_balances (account_id, balance, balance_date, currency, is_liability, credit_limit, notes)
SELECT id, 1639.00, '2026-02-08', 'SAR', true, 2000.00, 'Credit used = liability'
FROM finance.accounts WHERE name = 'Baseeta Credit'
ON CONFLICT DO NOTHING;

INSERT INTO finance.account_balances (account_id, balance, balance_date, currency, is_liability, credit_limit, notes)
SELECT id, 895.00, '2026-02-08', 'AED', true, 1000.00, 'Credit used = liability'
FROM finance.accounts WHERE name = 'Tabby Credit'
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 2. UNIFIED UPCOMING PAYMENTS VIEW
-- ============================================================================

CREATE OR REPLACE VIEW finance.v_upcoming_payments AS
WITH recurring_payments AS (
    -- Recurring items with calculated next due dates
    SELECT
        'recurring' as payment_type,
        ri.id as source_id,
        ri.name,
        ri.amount,
        ri.currency,
        ri.cadence,
        CASE
            -- If day_of_month is set, calculate next occurrence
            WHEN ri.day_of_month IS NOT NULL THEN
                CASE
                    WHEN EXTRACT(DAY FROM CURRENT_DATE) < ri.day_of_month
                    THEN DATE_TRUNC('month', CURRENT_DATE) + (ri.day_of_month - 1) * INTERVAL '1 day'
                    ELSE DATE_TRUNC('month', CURRENT_DATE + INTERVAL '1 month') + (ri.day_of_month - 1) * INTERVAL '1 day'
                END
            -- Otherwise use next_due_date or estimate
            WHEN ri.next_due_date IS NOT NULL THEN ri.next_due_date::date
            ELSE CURRENT_DATE + INTERVAL '30 days'
        END as due_date,
        NULL::integer as installments_remaining,
        NULL::numeric as total_remaining,
        ri.notes,
        ri.merchant_pattern,
        false as is_paid_this_period
    FROM finance.recurring_items ri
    WHERE ri.is_active = true
      AND ri.type = 'expense'
),
installment_payments AS (
    -- Active installments
    SELECT
        'installment' as payment_type,
        i.id as source_id,
        i.merchant as name,
        i.installment_amount as amount,
        i.currency,
        'monthly' as cadence,
        i.next_due_date::date as due_date,
        (i.installments_total - i.installments_paid) as installments_remaining,
        ((i.installments_total - i.installments_paid) * i.installment_amount) as total_remaining,
        i.notes,
        i.merchant as merchant_pattern,
        false as is_paid_this_period
    FROM finance.installments i
    WHERE i.status = 'active'
),
all_payments AS (
    SELECT * FROM recurring_payments
    UNION ALL
    SELECT * FROM installment_payments
)
SELECT
    payment_type,
    source_id,
    name,
    amount,
    currency,
    cadence,
    due_date::date,
    (due_date::date - CURRENT_DATE)::integer as days_until_due,
    installments_remaining,
    total_remaining,
    notes,
    merchant_pattern,
    CASE
        WHEN (due_date::date - CURRENT_DATE)::integer < 0 THEN 'overdue'
        WHEN (due_date::date - CURRENT_DATE)::integer <= 7 THEN 'due_soon'
        WHEN (due_date::date - CURRENT_DATE)::integer <= 30 THEN 'upcoming'
        ELSE 'future'
    END as urgency,
    is_paid_this_period
FROM all_payments
WHERE due_date IS NOT NULL
ORDER BY due_date ASC;

-- ============================================================================
-- 3. FINANCIAL POSITION SUMMARY FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION finance.get_financial_position()
RETURNS JSONB AS $$
DECLARE
    result JSONB;
    total_assets NUMERIC;
    total_liabilities NUMERIC;
    upcoming_30d NUMERIC;
BEGIN
    -- Calculate totals (convert SAR to AED: 1 SAR ≈ 0.98 AED)
    SELECT
        COALESCE(SUM(CASE WHEN NOT ab.is_liability THEN
            CASE WHEN ab.currency = 'SAR' THEN ab.balance * 0.98 ELSE ab.balance END
        ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN ab.is_liability THEN
            CASE WHEN ab.currency = 'SAR' THEN ab.balance * 0.98 ELSE ab.balance END
        ELSE 0 END), 0)
    INTO total_assets, total_liabilities
    FROM finance.account_balances ab
    INNER JOIN (
        SELECT account_id, MAX(balance_date) as max_date
        FROM finance.account_balances
        GROUP BY account_id
    ) latest ON ab.account_id = latest.account_id AND ab.balance_date = latest.max_date;

    -- Calculate upcoming payments in next 30 days
    SELECT COALESCE(SUM(
        CASE WHEN currency = 'SAR' THEN amount * 0.98 ELSE amount END
    ), 0)
    INTO upcoming_30d
    FROM finance.v_upcoming_payments
    WHERE days_until_due BETWEEN 0 AND 30;

    -- Build result
    result := jsonb_build_object(
        'summary', jsonb_build_object(
            'total_assets', total_assets,
            'total_liabilities', total_liabilities,
            'net_worth', total_assets - total_liabilities,
            'upcoming_30d', upcoming_30d,
            'available_after_bills', total_assets - upcoming_30d,
            'currency', 'AED',
            'as_of', CURRENT_DATE
        ),
        'accounts', (
            SELECT jsonb_agg(jsonb_build_object(
                'id', a.id,
                'name', a.name,
                'institution', a.institution,
                'type', a.account_type,
                'balance', ab.balance,
                'currency', ab.currency,
                'is_liability', ab.is_liability,
                'credit_limit', ab.credit_limit,
                'available_credit', CASE WHEN ab.is_liability AND ab.credit_limit IS NOT NULL
                    THEN ab.credit_limit - ab.balance ELSE NULL END,
                'balance_date', ab.balance_date
            ))
            FROM finance.accounts a
            LEFT JOIN finance.account_balances ab ON a.id = ab.account_id
            INNER JOIN (
                SELECT account_id, MAX(balance_date) as max_date
                FROM finance.account_balances
                GROUP BY account_id
            ) latest ON ab.account_id = latest.account_id AND ab.balance_date = latest.max_date
            WHERE a.is_active = true
        ),
        'upcoming_payments', (
            SELECT jsonb_agg(jsonb_build_object(
                'type', payment_type,
                'name', name,
                'amount', amount,
                'currency', currency,
                'due_date', due_date,
                'days_until_due', days_until_due,
                'urgency', urgency,
                'installments_remaining', installments_remaining,
                'total_remaining', total_remaining
            ))
            FROM finance.v_upcoming_payments
            WHERE days_until_due <= 60
            LIMIT 20
        ),
        'monthly_obligations', (
            SELECT jsonb_build_object(
                'recurring_total', COALESCE(SUM(CASE WHEN cadence = 'monthly' THEN amount ELSE 0 END), 0),
                'installments_total', COALESCE(SUM(CASE WHEN payment_type = 'installment' THEN amount ELSE 0 END), 0),
                'count', COUNT(*)
            )
            FROM finance.v_upcoming_payments
            WHERE days_until_due BETWEEN 0 AND 30
        )
    );

    RETURN result;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- 4. AUTO-RECONCILIATION: Mark recurring/installment as paid when transaction matches
-- ============================================================================

-- Function to check if a transaction matches an expected payment
CREATE OR REPLACE FUNCTION finance.reconcile_payment()
RETURNS TRIGGER AS $$
DECLARE
    matched_recurring RECORD;
    matched_installment RECORD;
BEGIN
    -- Only process expense transactions
    IF NEW.amount >= 0 THEN
        RETURN NEW;
    END IF;

    -- Try to match against recurring items by merchant pattern and approximate amount
    SELECT * INTO matched_recurring
    FROM finance.recurring_items ri
    WHERE ri.is_active = true
      AND ri.type = 'expense'
      AND ri.merchant_pattern IS NOT NULL
      AND NEW.merchant_name ILIKE ri.merchant_pattern
      AND ABS(ABS(NEW.amount) - ri.amount) < ri.amount * 0.15  -- within 15% tolerance
    LIMIT 1;

    IF FOUND THEN
        -- Update last_occurrence for the recurring item
        UPDATE finance.recurring_items
        SET last_occurrence = NEW.transaction_at,
            updated_at = NOW()
        WHERE id = matched_recurring.id;

        -- Add note to transaction
        UPDATE finance.transactions
        SET notes = COALESCE(notes, '') || ' [Matched: ' || matched_recurring.name || ']'
        WHERE id = NEW.id;
    END IF;

    -- Try to match against installments (Tabby, etc.)
    SELECT * INTO matched_installment
    FROM finance.installments i
    WHERE i.status = 'active'
      AND NEW.merchant_name ILIKE '%' || i.source || '%'
      AND ABS(ABS(NEW.amount) - i.installment_amount) < 1.00  -- within 1 AED
    LIMIT 1;

    IF FOUND THEN
        -- Increment installments_paid
        UPDATE finance.installments
        SET installments_paid = installments_paid + 1,
            next_due_date = CASE
                WHEN installments_paid + 1 >= installments_total THEN NULL
                ELSE next_due_date + INTERVAL '1 month'
            END,
            status = CASE
                WHEN installments_paid + 1 >= installments_total THEN 'completed'
                ELSE 'active'
            END,
            updated_at = NOW()
        WHERE id = matched_installment.id;

        -- Add note to transaction
        UPDATE finance.transactions
        SET notes = COALESCE(notes, '') || ' [Installment: ' || matched_installment.merchant || ' ' ||
            (matched_installment.installments_paid + 1) || '/' || matched_installment.installments_total || ']'
        WHERE id = NEW.id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for auto-reconciliation
DROP TRIGGER IF EXISTS trg_reconcile_payment ON finance.transactions;
CREATE TRIGGER trg_reconcile_payment
    AFTER INSERT ON finance.transactions
    FOR EACH ROW
    EXECUTE FUNCTION finance.reconcile_payment();

-- ============================================================================
-- 5. UPDATE RECURRING ITEMS WITH MERCHANT PATTERNS
-- ============================================================================

UPDATE finance.recurring_items SET merchant_pattern = '%DEWA%' WHERE name = 'DEWA' AND merchant_pattern IS NULL;
UPDATE finance.recurring_items SET merchant_pattern = '%LOGIC UTIL%' WHERE name ILIKE '%chiller%' AND merchant_pattern IS NULL;
UPDATE finance.recurring_items SET merchant_pattern = '%ETISALAT%' WHERE name ILIKE '%e& %' AND merchant_pattern IS NULL;
UPDATE finance.recurring_items SET merchant_pattern = '%DU %' WHERE name ILIKE '%du mobile%' AND merchant_pattern IS NULL;
UPDATE finance.recurring_items SET merchant_pattern = '%ANTHROPIC%' WHERE name ILIKE '%claude%' AND merchant_pattern IS NULL;
UPDATE finance.recurring_items SET merchant_pattern = '%OPENAI%' WHERE name ILIKE '%chatgpt%' AND merchant_pattern IS NULL;
UPDATE finance.recurring_items SET merchant_pattern = '%TASHEEL%' WHERE name ILIKE '%tasheel%' AND merchant_pattern IS NULL;
UPDATE finance.recurring_items SET merchant_pattern = '%APPLE.COM%' WHERE name ILIKE '%apple%' AND merchant_pattern IS NULL;

COMMIT;
