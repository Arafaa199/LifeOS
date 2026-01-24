-- Migration 031: Daily Finance Summary Generator
-- Purpose: Store and generate daily finance summaries for consumption
-- Created: 2026-01-24
-- Task: TASK-070

-- ============================================================================
-- 1. Daily Finance Summary Table (stores generated summaries)
-- ============================================================================
CREATE TABLE IF NOT EXISTS insights.daily_finance_summary (
    id SERIAL PRIMARY KEY,
    summary_date DATE NOT NULL UNIQUE,

    -- Yesterday's metrics
    yesterday_spent NUMERIC(12,2) DEFAULT 0,
    yesterday_txn_count INTEGER DEFAULT 0,
    yesterday_top_merchant VARCHAR(200),
    yesterday_top_category VARCHAR(50),
    yesterday_top_amount NUMERIC(12,2),

    -- MTD metrics
    mtd_spent NUMERIC(12,2) DEFAULT 0,
    mtd_income NUMERIC(12,2) DEFAULT 0,
    mtd_txn_count INTEGER DEFAULT 0,
    mtd_days_elapsed INTEGER DEFAULT 0,
    mtd_daily_avg NUMERIC(12,2) DEFAULT 0,

    -- Budget tracking
    mtd_vs_budget_pct NUMERIC(5,2),  -- % of monthly budget used
    projected_month_end NUMERIC(12,2),  -- Linear projection

    -- Top categories (JSONB for flexibility)
    top_categories JSONB,  -- [{category, amount, pct}]

    -- Anomalies
    anomaly_count INTEGER DEFAULT 0,
    anomalies JSONB,  -- [{merchant, amount, z_score, category}]

    -- Generated content
    markdown_summary TEXT,

    -- Metadata
    generated_at TIMESTAMPTZ DEFAULT NOW(),
    generation_duration_ms INTEGER
);

CREATE INDEX IF NOT EXISTS idx_daily_finance_summary_date ON insights.daily_finance_summary(summary_date DESC);

COMMENT ON TABLE insights.daily_finance_summary IS 'Daily finance summaries for consumption (idempotent per day)';

-- ============================================================================
-- 2. View: Yesterday Spending Details
-- ============================================================================
CREATE OR REPLACE VIEW insights.v_yesterday_spend AS
WITH yesterday AS (
    SELECT (CURRENT_DATE - INTERVAL '1 day')::date AS dt
)
SELECT
    y.dt AS summary_date,
    COALESCE(SUM(ABS(t.amount)) FILTER (WHERE t.amount < 0), 0) AS total_spent,
    COUNT(*) FILTER (WHERE t.amount < 0) AS txn_count,
    (
        SELECT merchant_name_clean
        FROM finance.transactions
        WHERE date = y.dt AND amount < 0 AND is_hidden = false
        GROUP BY merchant_name_clean
        ORDER BY SUM(ABS(amount)) DESC
        LIMIT 1
    ) AS top_merchant,
    (
        SELECT category
        FROM finance.transactions
        WHERE date = y.dt AND amount < 0 AND is_hidden = false
          AND category NOT IN ('Transfer')
        GROUP BY category
        ORDER BY SUM(ABS(amount)) DESC
        LIMIT 1
    ) AS top_category,
    MAX(ABS(t.amount)) FILTER (WHERE t.amount < 0) AS largest_txn
FROM yesterday y
LEFT JOIN finance.transactions t ON t.date = y.dt
    AND t.is_hidden = false
    AND t.is_quarantined = false
GROUP BY y.dt;

COMMENT ON VIEW insights.v_yesterday_spend IS 'Yesterday spending summary';

-- ============================================================================
-- 3. View: MTD (Month-to-Date) Metrics
-- ============================================================================
CREATE OR REPLACE VIEW insights.v_mtd_metrics AS
WITH current_month AS (
    SELECT
        date_trunc('month', CURRENT_DATE)::date AS month_start,
        CURRENT_DATE AS today,
        EXTRACT(DAY FROM CURRENT_DATE)::integer AS days_elapsed,
        (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month' - INTERVAL '1 day')::date AS month_end,
        EXTRACT(DAY FROM (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month' - INTERVAL '1 day'))::integer AS days_in_month
)
SELECT
    cm.month_start,
    cm.days_elapsed,
    cm.days_in_month,
    COALESCE(SUM(ABS(t.amount)) FILTER (WHERE t.amount < 0 AND t.category NOT IN ('Transfer')), 0) AS mtd_spent,
    COALESCE(SUM(t.amount) FILTER (WHERE t.amount > 0 AND t.category IN ('Income', 'Salary')), 0) AS mtd_income,
    COUNT(*) FILTER (WHERE t.amount < 0 AND t.category NOT IN ('Transfer')) AS mtd_txn_count,
    CASE
        WHEN cm.days_elapsed > 0
        THEN ROUND(COALESCE(SUM(ABS(t.amount)) FILTER (WHERE t.amount < 0 AND t.category NOT IN ('Transfer')), 0) / cm.days_elapsed, 2)
        ELSE 0
    END AS daily_avg,
    CASE
        WHEN cm.days_elapsed > 0
        THEN ROUND(
            (COALESCE(SUM(ABS(t.amount)) FILTER (WHERE t.amount < 0 AND t.category NOT IN ('Transfer')), 0) / cm.days_elapsed) * cm.days_in_month,
            2
        )
        ELSE 0
    END AS projected_month_end
FROM current_month cm
LEFT JOIN finance.transactions t ON t.date >= cm.month_start AND t.date <= cm.today
    AND t.is_hidden = false
    AND t.is_quarantined = false
GROUP BY cm.month_start, cm.days_elapsed, cm.days_in_month, cm.month_end;

COMMENT ON VIEW insights.v_mtd_metrics IS 'Month-to-date financial metrics';

-- ============================================================================
-- 4. View: MTD Top Categories
-- ============================================================================
CREATE OR REPLACE VIEW insights.v_mtd_top_categories AS
WITH current_month AS (
    SELECT date_trunc('month', CURRENT_DATE)::date AS month_start
),
category_totals AS (
    SELECT
        t.category,
        SUM(ABS(t.amount)) AS amount,
        COUNT(*) AS txn_count
    FROM finance.transactions t, current_month cm
    WHERE t.date >= cm.month_start
      AND t.date <= CURRENT_DATE
      AND t.amount < 0
      AND t.category NOT IN ('Transfer', 'Income', 'Salary')
      AND t.is_hidden = false
      AND t.is_quarantined = false
    GROUP BY t.category
),
total AS (
    SELECT SUM(amount) AS total_spent FROM category_totals
)
SELECT
    ct.category,
    ct.amount,
    ct.txn_count,
    ROUND((ct.amount / NULLIF(t.total_spent, 0)) * 100, 1) AS pct_of_total
FROM category_totals ct
CROSS JOIN total t
ORDER BY ct.amount DESC
LIMIT 5;

COMMENT ON VIEW insights.v_mtd_top_categories IS 'Top 5 spending categories MTD';

-- ============================================================================
-- 5. View: Recent Anomalies (last 7 days)
-- ============================================================================
CREATE OR REPLACE VIEW insights.v_recent_anomalies AS
SELECT
    id,
    date,
    merchant_name,
    category,
    currency,
    amount,
    z_score,
    anomaly_status
FROM finance.v_anomaly_baseline
WHERE anomaly_status = 'high_anomaly'
  AND date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY z_score DESC
LIMIT 10;

COMMENT ON VIEW insights.v_recent_anomalies IS 'High anomalies from last 7 days';

-- ============================================================================
-- 6. Function: Generate Daily Summary (idempotent)
-- ============================================================================
CREATE OR REPLACE FUNCTION insights.generate_daily_summary(target_date DATE DEFAULT CURRENT_DATE)
RETURNS INTEGER AS $$
DECLARE
    v_start_time TIMESTAMPTZ := clock_timestamp();
    v_yesterday RECORD;
    v_mtd RECORD;
    v_categories JSONB;
    v_anomalies JSONB;
    v_anomaly_count INTEGER;
    v_markdown TEXT;
    v_duration_ms INTEGER;
    v_summary_id INTEGER;
BEGIN
    -- Get yesterday's data (relative to target_date)
    SELECT
        COALESCE(SUM(ABS(amount)) FILTER (WHERE amount < 0), 0) AS spent,
        COUNT(*) FILTER (WHERE amount < 0) AS txn_count,
        (
            SELECT merchant_name_clean
            FROM finance.transactions
            WHERE date = target_date - 1 AND amount < 0 AND is_hidden = false
            GROUP BY merchant_name_clean
            ORDER BY SUM(ABS(amount)) DESC
            LIMIT 1
        ) AS top_merchant,
        (
            SELECT category
            FROM finance.transactions
            WHERE date = target_date - 1 AND amount < 0 AND is_hidden = false
              AND category NOT IN ('Transfer')
            GROUP BY category
            ORDER BY SUM(ABS(amount)) DESC
            LIMIT 1
        ) AS top_category,
        MAX(ABS(amount)) FILTER (WHERE amount < 0) AS top_amount
    INTO v_yesterday
    FROM finance.transactions
    WHERE date = target_date - 1
      AND is_hidden = false
      AND is_quarantined = false;

    -- Get MTD data (as of target_date)
    WITH month_range AS (
        SELECT
            date_trunc('month', target_date)::date AS month_start,
            EXTRACT(DAY FROM target_date)::integer AS days_elapsed,
            EXTRACT(DAY FROM (date_trunc('month', target_date) + INTERVAL '1 month' - INTERVAL '1 day'))::integer AS days_in_month
    )
    SELECT
        COALESCE(SUM(ABS(t.amount)) FILTER (WHERE t.amount < 0 AND t.category NOT IN ('Transfer')), 0) AS spent,
        COALESCE(SUM(t.amount) FILTER (WHERE t.amount > 0 AND t.category IN ('Income', 'Salary')), 0) AS income,
        COUNT(*) FILTER (WHERE t.amount < 0 AND t.category NOT IN ('Transfer')) AS txn_count,
        mr.days_elapsed,
        CASE WHEN mr.days_elapsed > 0
             THEN ROUND(COALESCE(SUM(ABS(t.amount)) FILTER (WHERE t.amount < 0 AND t.category NOT IN ('Transfer')), 0) / mr.days_elapsed, 2)
             ELSE 0 END AS daily_avg,
        CASE WHEN mr.days_elapsed > 0
             THEN ROUND((COALESCE(SUM(ABS(t.amount)) FILTER (WHERE t.amount < 0 AND t.category NOT IN ('Transfer')), 0) / mr.days_elapsed) * mr.days_in_month, 2)
             ELSE 0 END AS projected
    INTO v_mtd
    FROM month_range mr
    LEFT JOIN finance.transactions t ON t.date >= mr.month_start AND t.date <= target_date
        AND t.is_hidden = false
        AND t.is_quarantined = false
    GROUP BY mr.days_elapsed, mr.days_in_month;

    -- Get top categories as JSONB
    SELECT jsonb_agg(row_to_json(cat))
    INTO v_categories
    FROM (
        SELECT category, SUM(ABS(amount)) AS amount
        FROM finance.transactions
        WHERE date >= date_trunc('month', target_date)::date
          AND date <= target_date
          AND amount < 0
          AND category NOT IN ('Transfer', 'Income', 'Salary')
          AND is_hidden = false
          AND is_quarantined = false
        GROUP BY category
        ORDER BY SUM(ABS(amount)) DESC
        LIMIT 5
    ) cat;

    -- Get recent anomalies
    SELECT
        COUNT(*),
        COALESCE(jsonb_agg(row_to_json(a)), '[]'::jsonb)
    INTO v_anomaly_count, v_anomalies
    FROM (
        SELECT merchant_name, ABS(amount) as amount, z_score, category
        FROM finance.v_anomaly_baseline
        WHERE anomaly_status = 'high_anomaly'
          AND date >= target_date - INTERVAL '7 days'
        ORDER BY z_score DESC
        LIMIT 5
    ) a;

    -- Generate markdown summary
    v_markdown := format(
        E'# Daily Finance Summary: %s\n\n' ||
        E'## Yesterday (%s)\n' ||
        E'- **Spent**: %s\n' ||
        E'- **Transactions**: %s\n' ||
        E'- **Top Merchant**: %s\n' ||
        E'- **Top Category**: %s\n' ||
        E'- **Largest Transaction**: %s\n\n' ||
        E'## Month-to-Date\n' ||
        E'- **Total Spent**: %s\n' ||
        E'- **Total Income**: %s\n' ||
        E'- **Net**: %s\n' ||
        E'- **Daily Average**: %s\n' ||
        E'- **Projected End-of-Month**: %s\n' ||
        E'- **Days Elapsed**: %s\n\n' ||
        E'## Anomalies (%s high)\n' ||
        E'%s\n\n' ||
        E'---\n*Generated: %s*\n',
        target_date::text,
        (target_date - 1)::text,
        COALESCE(v_yesterday.spent::text, '0'),
        COALESCE(v_yesterday.txn_count::text, '0'),
        COALESCE(v_yesterday.top_merchant, 'N/A'),
        COALESCE(v_yesterday.top_category, 'N/A'),
        COALESCE(v_yesterday.top_amount::text, '0'),
        COALESCE(v_mtd.spent::text, '0'),
        COALESCE(v_mtd.income::text, '0'),
        COALESCE((v_mtd.income - v_mtd.spent)::text, '0'),
        COALESCE(v_mtd.daily_avg::text, '0'),
        COALESCE(v_mtd.projected::text, '0'),
        COALESCE(v_mtd.days_elapsed::text, '0'),
        v_anomaly_count::text,
        CASE WHEN v_anomaly_count > 0
             THEN (SELECT string_agg(format('- %s: %s (z=%s)', a->>'merchant_name', a->>'amount', a->>'z_score'), E'\n')
                   FROM jsonb_array_elements(v_anomalies) a)
             ELSE 'None detected' END,
        NOW()::text
    );

    -- Calculate duration
    v_duration_ms := EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_start_time))::integer;

    -- Upsert the summary (idempotent)
    INSERT INTO insights.daily_finance_summary (
        summary_date,
        yesterday_spent, yesterday_txn_count, yesterday_top_merchant, yesterday_top_category, yesterday_top_amount,
        mtd_spent, mtd_income, mtd_txn_count, mtd_days_elapsed, mtd_daily_avg,
        projected_month_end,
        top_categories,
        anomaly_count, anomalies,
        markdown_summary,
        generated_at, generation_duration_ms
    ) VALUES (
        target_date,
        v_yesterday.spent, v_yesterday.txn_count, v_yesterday.top_merchant, v_yesterday.top_category, v_yesterday.top_amount,
        v_mtd.spent, v_mtd.income, v_mtd.txn_count, v_mtd.days_elapsed, v_mtd.daily_avg,
        v_mtd.projected,
        v_categories,
        v_anomaly_count, v_anomalies,
        v_markdown,
        NOW(), v_duration_ms
    )
    ON CONFLICT (summary_date) DO UPDATE SET
        yesterday_spent = EXCLUDED.yesterday_spent,
        yesterday_txn_count = EXCLUDED.yesterday_txn_count,
        yesterday_top_merchant = EXCLUDED.yesterday_top_merchant,
        yesterday_top_category = EXCLUDED.yesterday_top_category,
        yesterday_top_amount = EXCLUDED.yesterday_top_amount,
        mtd_spent = EXCLUDED.mtd_spent,
        mtd_income = EXCLUDED.mtd_income,
        mtd_txn_count = EXCLUDED.mtd_txn_count,
        mtd_days_elapsed = EXCLUDED.mtd_days_elapsed,
        mtd_daily_avg = EXCLUDED.mtd_daily_avg,
        projected_month_end = EXCLUDED.projected_month_end,
        top_categories = EXCLUDED.top_categories,
        anomaly_count = EXCLUDED.anomaly_count,
        anomalies = EXCLUDED.anomalies,
        markdown_summary = EXCLUDED.markdown_summary,
        generated_at = NOW(),
        generation_duration_ms = EXCLUDED.generation_duration_ms
    RETURNING id INTO v_summary_id;

    RETURN v_summary_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION insights.generate_daily_summary(DATE) IS 'Generate daily finance summary (idempotent upsert)';

-- ============================================================================
-- 7. Grant permissions
-- ============================================================================
GRANT SELECT ON insights.daily_finance_summary TO nexus;
GRANT SELECT ON insights.v_yesterday_spend TO nexus;
GRANT SELECT ON insights.v_mtd_metrics TO nexus;
GRANT SELECT ON insights.v_mtd_top_categories TO nexus;
GRANT SELECT ON insights.v_recent_anomalies TO nexus;
GRANT EXECUTE ON FUNCTION insights.generate_daily_summary(DATE) TO nexus;
