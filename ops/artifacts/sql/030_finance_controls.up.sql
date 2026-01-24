-- Migration 030: Finance Controls (Phase 1.5)
-- Creates cashflow_events, wishlist, config_changes audit table, and planning views
-- Source: Financial_Tracker_2025.xlsx → finance_config.yaml

-- ============================================
-- 1. CASHFLOW EVENTS (One-time financial events)
-- ============================================
CREATE TABLE IF NOT EXISTS finance.cashflow_events (
    id SERIAL PRIMARY KEY,
    event_date DATE NOT NULL,
    event_name VARCHAR(200) NOT NULL,
    amount NUMERIC(12,2) NOT NULL,  -- Positive = income, Negative = expense
    currency VARCHAR(3) DEFAULT 'AED',
    event_type VARCHAR(20) NOT NULL CHECK (event_type IN ('income', 'expense', 'transfer')),
    priority VARCHAR(20) DEFAULT 'medium' CHECK (priority IN ('critical', 'high', 'medium', 'low')),
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'cancelled', 'deferred')),
    category_id INTEGER REFERENCES finance.categories(id),
    linked_transaction_id INTEGER REFERENCES finance.transactions(id),
    notes TEXT,
    source VARCHAR(50) DEFAULT 'manual',  -- manual, import, system
    external_id VARCHAR(100),  -- For idempotent imports
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Unique constraint for idempotent imports
CREATE UNIQUE INDEX IF NOT EXISTS idx_cashflow_events_external_id
    ON finance.cashflow_events(external_id) WHERE external_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_cashflow_events_date ON finance.cashflow_events(event_date);
CREATE INDEX IF NOT EXISTS idx_cashflow_events_status ON finance.cashflow_events(status) WHERE status = 'pending';

COMMENT ON TABLE finance.cashflow_events IS 'One-time financial events (loan arrival, large purchases, tax payments, etc.)';

-- ============================================
-- 2. WISHLIST
-- ============================================
CREATE TABLE IF NOT EXISTS finance.wishlist (
    id SERIAL PRIMARY KEY,
    item_name VARCHAR(200) NOT NULL,
    estimated_cost NUMERIC(10,2) NOT NULL,
    actual_cost NUMERIC(10,2),
    currency VARCHAR(3) DEFAULT 'AED',
    priority VARCHAR(20) DEFAULT 'medium' CHECK (priority IN ('critical', 'high', 'medium', 'low')),
    category VARCHAR(50),  -- health, tech, security, other
    target_date DATE,
    purchased_date DATE,
    status VARCHAR(20) DEFAULT 'wanted' CHECK (status IN ('wanted', 'saving', 'purchased', 'cancelled')),
    funding_source VARCHAR(50),  -- cash, tabby, loan, etc.
    linked_transaction_id INTEGER REFERENCES finance.transactions(id),
    notes TEXT,
    external_id VARCHAR(100),  -- For idempotent imports
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_wishlist_external_id
    ON finance.wishlist(external_id) WHERE external_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_wishlist_status ON finance.wishlist(status);
CREATE INDEX IF NOT EXISTS idx_wishlist_priority ON finance.wishlist(priority);

COMMENT ON TABLE finance.wishlist IS 'Wishlist items with priority and target dates';

-- ============================================
-- 3. CONFIG CHANGES (Audit Table)
-- ============================================
CREATE TABLE IF NOT EXISTS finance.config_changes (
    id SERIAL PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    record_id INTEGER,
    operation VARCHAR(20) NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE', 'IMPORT')),
    old_values JSONB,
    new_values JSONB,
    changed_by VARCHAR(100) DEFAULT 'system',
    change_source VARCHAR(50),  -- import, api, manual
    change_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_config_changes_table ON finance.config_changes(table_name);
CREATE INDEX IF NOT EXISTS idx_config_changes_created ON finance.config_changes(created_at);

COMMENT ON TABLE finance.config_changes IS 'Audit log for finance configuration changes';

-- ============================================
-- 4. VIEW: Monthly Budget vs Actual
-- ============================================
CREATE OR REPLACE VIEW finance.monthly_budget_vs_actual AS
WITH monthly_actuals AS (
    SELECT
        DATE_TRUNC('month', transaction_at AT TIME ZONE 'Asia/Dubai')::date AS month,
        COALESCE(c.name, t.category, 'Uncategorized') AS category,
        SUM(CASE WHEN t.amount < 0 THEN ABS(t.amount) ELSE 0 END) AS actual_spent,
        COUNT(*) AS transaction_count
    FROM finance.transactions t
    LEFT JOIN finance.categories c ON t.category = c.name
    WHERE t.is_hidden = false
      AND t.is_quarantined = false
      AND t.amount < 0  -- Only expenses
      AND t.category NOT IN ('Transfer', 'Income', 'Salary')
    GROUP BY 1, 2
),
budget_with_actuals AS (
    SELECT
        b.month,
        b.category,
        b.budget_amount,
        COALESCE(ma.actual_spent, 0) AS actual_spent,
        COALESCE(ma.transaction_count, 0) AS transaction_count,
        b.budget_amount - COALESCE(ma.actual_spent, 0) AS variance,
        CASE
            WHEN b.budget_amount > 0 THEN
                ROUND((COALESCE(ma.actual_spent, 0) / b.budget_amount) * 100, 1)
            ELSE 0
        END AS pct_used,
        CASE
            WHEN COALESCE(ma.actual_spent, 0) > b.budget_amount * 1.1 THEN 'over_budget'
            WHEN COALESCE(ma.actual_spent, 0) > b.budget_amount * 0.9 THEN 'near_limit'
            ELSE 'on_track'
        END AS status
    FROM finance.budgets b
    LEFT JOIN monthly_actuals ma ON b.month = ma.month
        AND LOWER(b.category) = LOWER(ma.category)
)
SELECT * FROM budget_with_actuals
ORDER BY month DESC, category;

COMMENT ON VIEW finance.monthly_budget_vs_actual IS 'Compares budgeted amounts to actual spending by category and month';

-- ============================================
-- 5. VIEW: Runway Projection (Next 60 Days)
-- ============================================
CREATE OR REPLACE VIEW finance.runway_projection_next_60d AS
WITH RECURSIVE date_series AS (
    SELECT CURRENT_DATE AS day, 1 AS day_num
    UNION ALL
    SELECT day + 1, day_num + 1
    FROM date_series
    WHERE day_num < 60
),
-- Get current balance (simplified: sum of all transactions)
current_balance AS (
    SELECT COALESCE(SUM(amount), 0) AS balance
    FROM finance.transactions
    WHERE is_hidden = false
      AND is_quarantined = false
      AND transaction_at <= NOW()
),
-- Recurring bills due in next 60 days
upcoming_bills AS (
    SELECT
        CASE
            WHEN ri.cadence = 'monthly' THEN
                MAKE_DATE(
                    EXTRACT(YEAR FROM CURRENT_DATE + (n || ' months')::interval)::int,
                    EXTRACT(MONTH FROM CURRENT_DATE + (n || ' months')::interval)::int,
                    LEAST(ri.day_of_month, 28)
                )
            WHEN ri.cadence = 'quarterly' THEN ri.next_due_date
            WHEN ri.cadence = 'yearly' THEN ri.next_due_date
            ELSE ri.next_due_date
        END AS due_date,
        ri.name,
        -ABS(ri.amount) AS amount,  -- Bills are outflows
        'recurring_bill' AS source
    FROM finance.recurring_items ri
    CROSS JOIN generate_series(0, 2) AS n  -- Next 3 occurrences for monthly
    WHERE ri.is_active = true
      AND ri.type = 'expense'
),
-- One-time events
upcoming_events AS (
    SELECT
        event_date AS due_date,
        event_name AS name,
        amount,
        'cashflow_event' AS source
    FROM finance.cashflow_events
    WHERE status = 'pending'
      AND event_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 60
),
-- Combine all future cashflows
all_cashflows AS (
    SELECT due_date, name, amount, source FROM upcoming_bills WHERE due_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 60
    UNION ALL
    SELECT due_date, name, amount, source FROM upcoming_events
),
-- Running balance projection
daily_projection AS (
    SELECT
        ds.day,
        ds.day_num,
        (SELECT balance FROM current_balance) AS starting_balance,
        COALESCE(SUM(ac.amount), 0) AS day_cashflow,
        STRING_AGG(ac.name || ' (' || ac.amount || ')', ', ') AS events
    FROM date_series ds
    LEFT JOIN all_cashflows ac ON ac.due_date = ds.day
    GROUP BY ds.day, ds.day_num
)
SELECT
    day,
    day_num,
    starting_balance,
    day_cashflow,
    events,
    starting_balance + SUM(day_cashflow) OVER (ORDER BY day) AS projected_balance,
    CASE
        WHEN starting_balance + SUM(day_cashflow) OVER (ORDER BY day) < 0 THEN 'negative'
        WHEN starting_balance + SUM(day_cashflow) OVER (ORDER BY day) < 5000 THEN 'low'
        ELSE 'healthy'
    END AS balance_status
FROM daily_projection
ORDER BY day;

COMMENT ON VIEW finance.runway_projection_next_60d IS 'Projects account balance for next 60 days based on recurring bills and scheduled events';

-- ============================================
-- 6. VIEW: Top Risks Next 30 Days
-- ============================================
CREATE OR REPLACE VIEW finance.top_risks_next_30d AS
WITH current_balance AS (
    SELECT COALESCE(SUM(amount), 0) AS balance
    FROM finance.transactions
    WHERE is_hidden = false
      AND is_quarantined = false
      AND transaction_at <= NOW()
),
-- Large upcoming expenses
large_expenses AS (
    SELECT
        event_date AS risk_date,
        event_name AS risk_description,
        ABS(amount) AS risk_amount,
        'large_expense' AS risk_type,
        priority,
        CASE
            WHEN ABS(amount) > (SELECT balance FROM current_balance) * 0.5 THEN 'critical'
            WHEN ABS(amount) > (SELECT balance FROM current_balance) * 0.3 THEN 'high'
            ELSE 'medium'
        END AS calculated_severity
    FROM finance.cashflow_events
    WHERE status = 'pending'
      AND event_type = 'expense'
      AND event_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 30
      AND ABS(amount) > 1000  -- Only significant amounts
),
-- Budget overruns (current month)
budget_overruns AS (
    SELECT
        DATE_TRUNC('month', CURRENT_DATE)::date AS risk_date,
        'Budget overrun: ' || category AS risk_description,
        actual_spent - budget_amount AS risk_amount,
        'budget_overrun' AS risk_type,
        'medium' AS priority,
        CASE
            WHEN (actual_spent - budget_amount) > budget_amount * 0.3 THEN 'high'
            ELSE 'medium'
        END AS calculated_severity
    FROM finance.monthly_budget_vs_actual
    WHERE month = DATE_TRUNC('month', CURRENT_DATE)::date
      AND actual_spent > budget_amount
),
-- Recurring bills that might cause low balance
recurring_risks AS (
    SELECT
        ri.next_due_date AS risk_date,
        'Recurring bill: ' || ri.name AS risk_description,
        ABS(ri.amount) AS risk_amount,
        'recurring_bill' AS risk_type,
        'medium' AS priority,
        CASE
            WHEN ABS(ri.amount) > 5000 THEN 'high'
            ELSE 'medium'
        END AS calculated_severity
    FROM finance.recurring_items ri
    WHERE ri.is_active = true
      AND ri.type = 'expense'
      AND ri.next_due_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 30
      AND ABS(ri.amount) > 2000  -- Only significant bills
),
-- Combine all risks
all_risks AS (
    SELECT * FROM large_expenses
    UNION ALL
    SELECT * FROM budget_overruns
    UNION ALL
    SELECT * FROM recurring_risks
)
SELECT
    risk_date,
    risk_description,
    risk_amount,
    risk_type,
    priority,
    calculated_severity,
    ROW_NUMBER() OVER (ORDER BY
        CASE calculated_severity
            WHEN 'critical' THEN 1
            WHEN 'high' THEN 2
            ELSE 3
        END,
        risk_amount DESC
    ) AS risk_rank
FROM all_risks
ORDER BY risk_rank
LIMIT 10;

COMMENT ON VIEW finance.top_risks_next_30d IS 'Top 10 financial risks in the next 30 days';

-- ============================================
-- 7. Function to import from config
-- ============================================
CREATE OR REPLACE FUNCTION finance.import_cashflow_event(
    p_external_id VARCHAR,
    p_event_date DATE,
    p_event_name VARCHAR,
    p_amount NUMERIC,
    p_event_type VARCHAR,
    p_priority VARCHAR DEFAULT 'medium',
    p_notes TEXT DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO finance.cashflow_events (
        external_id, event_date, event_name, amount, event_type, priority, notes, source
    ) VALUES (
        p_external_id, p_event_date, p_event_name, p_amount, p_event_type, p_priority, p_notes, 'import'
    )
    ON CONFLICT (external_id) WHERE external_id IS NOT NULL
    DO UPDATE SET
        event_date = EXCLUDED.event_date,
        event_name = EXCLUDED.event_name,
        amount = EXCLUDED.amount,
        priority = EXCLUDED.priority,
        notes = EXCLUDED.notes,
        updated_at = NOW()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION finance.import_wishlist_item(
    p_external_id VARCHAR,
    p_item_name VARCHAR,
    p_estimated_cost NUMERIC,
    p_priority VARCHAR DEFAULT 'medium',
    p_category VARCHAR DEFAULT NULL,
    p_target_date DATE DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO finance.wishlist (
        external_id, item_name, estimated_cost, priority, category, target_date, notes
    ) VALUES (
        p_external_id, p_item_name, p_estimated_cost, p_priority, p_category, p_target_date, p_notes
    )
    ON CONFLICT (external_id) WHERE external_id IS NOT NULL
    DO UPDATE SET
        item_name = EXCLUDED.item_name,
        estimated_cost = EXCLUDED.estimated_cost,
        priority = EXCLUDED.priority,
        category = EXCLUDED.category,
        target_date = EXCLUDED.target_date,
        notes = EXCLUDED.notes,
        updated_at = NOW()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 8. Trigger for audit logging
-- ============================================
CREATE OR REPLACE FUNCTION finance.log_config_change()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO finance.config_changes (table_name, record_id, operation, new_values)
        VALUES (TG_TABLE_NAME, NEW.id, 'INSERT', to_jsonb(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO finance.config_changes (table_name, record_id, operation, old_values, new_values)
        VALUES (TG_TABLE_NAME, NEW.id, 'UPDATE', to_jsonb(OLD), to_jsonb(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO finance.config_changes (table_name, record_id, operation, old_values)
        VALUES (TG_TABLE_NAME, OLD.id, 'DELETE', to_jsonb(OLD));
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Apply audit triggers
DROP TRIGGER IF EXISTS tr_audit_cashflow_events ON finance.cashflow_events;
CREATE TRIGGER tr_audit_cashflow_events
    AFTER INSERT OR UPDATE OR DELETE ON finance.cashflow_events
    FOR EACH ROW EXECUTE FUNCTION finance.log_config_change();

DROP TRIGGER IF EXISTS tr_audit_wishlist ON finance.wishlist;
CREATE TRIGGER tr_audit_wishlist
    AFTER INSERT OR UPDATE OR DELETE ON finance.wishlist
    FOR EACH ROW EXECUTE FUNCTION finance.log_config_change();

DROP TRIGGER IF EXISTS tr_audit_budgets ON finance.budgets;
CREATE TRIGGER tr_audit_budgets
    AFTER INSERT OR UPDATE OR DELETE ON finance.budgets
    FOR EACH ROW EXECUTE FUNCTION finance.log_config_change();

DROP TRIGGER IF EXISTS tr_audit_recurring_items ON finance.recurring_items;
CREATE TRIGGER tr_audit_recurring_items
    AFTER INSERT OR UPDATE OR DELETE ON finance.recurring_items
    FOR EACH ROW EXECUTE FUNCTION finance.log_config_change();
