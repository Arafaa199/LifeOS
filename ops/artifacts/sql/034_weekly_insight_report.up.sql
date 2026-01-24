-- Migration 034: Weekly Insight Markdown Report
-- Purpose: Generate weekly markdown summaries with trends
-- Created: 2026-01-24
-- Task: TASK-073

-- ============================================================================
-- 1. Weekly Insight Reports Table
-- ============================================================================
CREATE TABLE IF NOT EXISTS insights.weekly_reports (
    id SERIAL PRIMARY KEY,
    week_start DATE NOT NULL UNIQUE,  -- Monday of the week
    week_end DATE NOT NULL,

    -- Health metrics
    avg_recovery NUMERIC(5,2),
    avg_hrv NUMERIC(6,2),
    avg_sleep_hours NUMERIC(4,2),
    recovery_trend VARCHAR(20),  -- improving, declining, stable

    -- Finance metrics
    total_spent NUMERIC(12,2),
    total_income NUMERIC(12,2),
    top_category VARCHAR(50),
    budget_alerts INTEGER,
    spending_trend VARCHAR(20),

    -- Productivity metrics
    total_commits INTEGER,
    active_days INTEGER,
    productivity_trend VARCHAR(20),

    -- Behavioral metrics
    avg_tv_hours NUMERIC(4,2),
    sleep_consistency VARCHAR(20),

    -- Anomalies and alerts
    anomaly_count INTEGER,
    critical_alerts INTEGER,

    -- Generated content
    markdown_report TEXT,
    highlights JSONB,  -- Key insights

    -- Metadata
    generated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_weekly_reports_week ON insights.weekly_reports(week_start DESC);

COMMENT ON TABLE insights.weekly_reports IS 'Weekly insight summaries with markdown reports';

-- ============================================================================
-- 2. Weekly Health Summary View
-- ============================================================================
CREATE OR REPLACE VIEW insights.v_weekly_health AS
WITH weeks AS (
    SELECT
        date_trunc('week', d)::date AS week_start,
        (date_trunc('week', d) + INTERVAL '6 days')::date AS week_end
    FROM generate_series(
        CURRENT_DATE - INTERVAL '8 weeks',
        CURRENT_DATE,
        '1 week'::interval
    ) d
)
SELECT
    w.week_start,
    w.week_end,
    ROUND(AVG(wr.recovery_score), 1) AS avg_recovery,
    ROUND(AVG(wr.hrv_rmssd), 1) AS avg_hrv,
    ROUND(AVG(wr.rhr), 1) AS avg_rhr,
    COUNT(wr.date) AS days_with_data
FROM weeks w
LEFT JOIN health.whoop_recovery wr ON wr.date BETWEEN w.week_start AND w.week_end
GROUP BY w.week_start, w.week_end
ORDER BY w.week_start DESC;

COMMENT ON VIEW insights.v_weekly_health IS 'Weekly health metrics aggregates';

-- ============================================================================
-- 3. Weekly Finance Summary View
-- ============================================================================
CREATE OR REPLACE VIEW insights.v_weekly_finance AS
WITH weeks AS (
    SELECT
        date_trunc('week', d)::date AS week_start,
        (date_trunc('week', d) + INTERVAL '6 days')::date AS week_end
    FROM generate_series(
        CURRENT_DATE - INTERVAL '8 weeks',
        CURRENT_DATE,
        '1 week'::interval
    ) d
)
SELECT
    w.week_start,
    w.week_end,
    COALESCE(SUM(ABS(t.amount)) FILTER (WHERE t.amount < 0 AND t.category NOT IN ('Transfer')), 0) AS total_spent,
    COALESCE(SUM(t.amount) FILTER (WHERE t.amount > 0 AND t.category IN ('Income', 'Salary')), 0) AS total_income,
    COUNT(*) FILTER (WHERE t.amount < 0) AS txn_count,
    (
        SELECT category FROM finance.transactions
        WHERE date BETWEEN w.week_start AND w.week_end
          AND amount < 0 AND category NOT IN ('Transfer')
          AND is_hidden = false
        GROUP BY category ORDER BY SUM(ABS(amount)) DESC LIMIT 1
    ) AS top_category
FROM weeks w
LEFT JOIN finance.transactions t ON t.date BETWEEN w.week_start AND w.week_end
    AND t.is_hidden = false AND t.is_quarantined = false
GROUP BY w.week_start, w.week_end
ORDER BY w.week_start DESC;

COMMENT ON VIEW insights.v_weekly_finance IS 'Weekly finance metrics aggregates';

-- ============================================================================
-- 4. Weekly Productivity Summary View
-- ============================================================================
CREATE OR REPLACE VIEW insights.v_weekly_productivity AS
WITH weeks AS (
    SELECT
        date_trunc('week', d)::date AS week_start,
        (date_trunc('week', d) + INTERVAL '6 days')::date AS week_end
    FROM generate_series(
        CURRENT_DATE - INTERVAL '8 weeks',
        CURRENT_DATE,
        '1 week'::interval
    ) d
)
SELECT
    w.week_start,
    w.week_end,
    COALESCE(SUM((ge.payload->>'size')::int) FILTER (WHERE ge.event_type = 'PushEvent'), 0) AS total_commits,
    COUNT(DISTINCT ge.created_at_github::date) AS active_days,
    COUNT(DISTINCT ge.repo_name) AS repos_touched
FROM weeks w
LEFT JOIN raw.github_events ge ON ge.created_at_github::date BETWEEN w.week_start AND w.week_end
GROUP BY w.week_start, w.week_end
ORDER BY w.week_start DESC;

COMMENT ON VIEW insights.v_weekly_productivity IS 'Weekly productivity metrics from GitHub';

-- ============================================================================
-- 5. Generate Weekly Report Function
-- ============================================================================
CREATE OR REPLACE FUNCTION insights.generate_weekly_report(target_week_start DATE DEFAULT NULL)
RETURNS INTEGER AS $$
DECLARE
    v_week_start DATE;
    v_week_end DATE;
    v_health RECORD;
    v_finance RECORD;
    v_productivity RECORD;
    v_prev_health RECORD;
    v_prev_finance RECORD;
    v_anomaly_count INTEGER;
    v_critical_alerts INTEGER;
    v_budget_alerts INTEGER;
    v_markdown TEXT;
    v_highlights JSONB;
    v_report_id INTEGER;
BEGIN
    -- Default to last complete week (Monday-Sunday)
    IF target_week_start IS NULL THEN
        v_week_start := date_trunc('week', CURRENT_DATE - INTERVAL '7 days')::date;
    ELSE
        v_week_start := target_week_start;
    END IF;
    v_week_end := v_week_start + INTERVAL '6 days';

    -- Get current week health data
    SELECT * INTO v_health FROM insights.v_weekly_health WHERE week_start = v_week_start;

    -- Get previous week for comparison
    SELECT * INTO v_prev_health FROM insights.v_weekly_health WHERE week_start = v_week_start - INTERVAL '7 days';

    -- Get finance data
    SELECT * INTO v_finance FROM insights.v_weekly_finance WHERE week_start = v_week_start;
    SELECT * INTO v_prev_finance FROM insights.v_weekly_finance WHERE week_start = v_week_start - INTERVAL '7 days';

    -- Get productivity data
    SELECT * INTO v_productivity FROM insights.v_weekly_productivity WHERE week_start = v_week_start;

    -- Get anomaly and alert counts
    SELECT COUNT(*) INTO v_anomaly_count
    FROM insights.daily_anomalies
    WHERE day BETWEEN v_week_start AND v_week_end;

    SELECT COUNT(*) INTO v_critical_alerts
    FROM ops.pipeline_alerts
    WHERE severity = 'critical'
      AND created_at BETWEEN v_week_start AND v_week_end + INTERVAL '1 day';

    SELECT COUNT(*) INTO v_budget_alerts
    FROM ops.pipeline_alerts
    WHERE alert_type LIKE 'budget_%'
      AND created_at BETWEEN v_week_start AND v_week_end + INTERVAL '1 day';

    -- Build highlights
    v_highlights := jsonb_build_object(
        'health_trend', CASE
            WHEN v_prev_health.avg_recovery IS NULL THEN 'no_data'
            WHEN v_health.avg_recovery > v_prev_health.avg_recovery + 5 THEN 'improving'
            WHEN v_health.avg_recovery < v_prev_health.avg_recovery - 5 THEN 'declining'
            ELSE 'stable'
        END,
        'spending_trend', CASE
            WHEN v_prev_finance.total_spent IS NULL OR v_prev_finance.total_spent = 0 THEN 'no_data'
            WHEN v_finance.total_spent > v_prev_finance.total_spent * 1.2 THEN 'increasing'
            WHEN v_finance.total_spent < v_prev_finance.total_spent * 0.8 THEN 'decreasing'
            ELSE 'stable'
        END,
        'top_insight', CASE
            WHEN v_health.avg_recovery < 50 THEN 'Low recovery week - prioritize rest'
            WHEN v_finance.total_spent > 5000 THEN 'High spending week'
            WHEN v_productivity.total_commits > 50 THEN 'Productive coding week'
            ELSE 'Normal week'
        END
    );

    -- Generate markdown report
    v_markdown := format(
        E'# Weekly Insight Report\n' ||
        E'**Week:** %s to %s\n\n' ||
        E'---\n\n' ||
        E'## Health\n' ||
        E'- **Average Recovery:** %s%% %s\n' ||
        E'- **Average HRV:** %s\n' ||
        E'- **Days with Data:** %s/7\n\n' ||
        E'## Finance\n' ||
        E'- **Total Spent:** %s\n' ||
        E'- **Total Income:** %s\n' ||
        E'- **Top Category:** %s\n' ||
        E'- **Budget Alerts:** %s\n\n' ||
        E'## Productivity\n' ||
        E'- **Commits:** %s\n' ||
        E'- **Active Days:** %s\n' ||
        E'- **Repos Touched:** %s\n\n' ||
        E'## Alerts & Anomalies\n' ||
        E'- **Anomalies Detected:** %s\n' ||
        E'- **Critical Alerts:** %s\n\n' ||
        E'---\n' ||
        E'*Generated: %s*\n',
        v_week_start::text,
        v_week_end::text,
        COALESCE(v_health.avg_recovery::text, 'N/A'),
        CASE (v_highlights->>'health_trend')
            WHEN 'improving' THEN '↑'
            WHEN 'declining' THEN '↓'
            ELSE '→'
        END,
        COALESCE(v_health.avg_hrv::text, 'N/A'),
        COALESCE(v_health.days_with_data::text, '0'),
        COALESCE(v_finance.total_spent::text, '0'),
        COALESCE(v_finance.total_income::text, '0'),
        COALESCE(v_finance.top_category, 'N/A'),
        v_budget_alerts::text,
        COALESCE(v_productivity.total_commits::text, '0'),
        COALESCE(v_productivity.active_days::text, '0'),
        COALESCE(v_productivity.repos_touched::text, '0'),
        v_anomaly_count::text,
        v_critical_alerts::text,
        NOW()::text
    );

    -- Upsert report
    INSERT INTO insights.weekly_reports (
        week_start, week_end,
        avg_recovery, avg_hrv, recovery_trend,
        total_spent, total_income, top_category, budget_alerts, spending_trend,
        total_commits, active_days, productivity_trend,
        anomaly_count, critical_alerts,
        markdown_report, highlights
    ) VALUES (
        v_week_start, v_week_end,
        v_health.avg_recovery, v_health.avg_hrv, v_highlights->>'health_trend',
        v_finance.total_spent, v_finance.total_income, v_finance.top_category, v_budget_alerts, v_highlights->>'spending_trend',
        v_productivity.total_commits, v_productivity.active_days, NULL,
        v_anomaly_count, v_critical_alerts,
        v_markdown, v_highlights
    )
    ON CONFLICT (week_start) DO UPDATE SET
        avg_recovery = EXCLUDED.avg_recovery,
        avg_hrv = EXCLUDED.avg_hrv,
        recovery_trend = EXCLUDED.recovery_trend,
        total_spent = EXCLUDED.total_spent,
        total_income = EXCLUDED.total_income,
        top_category = EXCLUDED.top_category,
        budget_alerts = EXCLUDED.budget_alerts,
        spending_trend = EXCLUDED.spending_trend,
        total_commits = EXCLUDED.total_commits,
        active_days = EXCLUDED.active_days,
        anomaly_count = EXCLUDED.anomaly_count,
        critical_alerts = EXCLUDED.critical_alerts,
        markdown_report = EXCLUDED.markdown_report,
        highlights = EXCLUDED.highlights,
        generated_at = NOW()
    RETURNING id INTO v_report_id;

    RETURN v_report_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION insights.generate_weekly_report(DATE) IS 'Generate weekly insight report with markdown (idempotent)';

-- ============================================================================
-- 6. Grant Permissions
-- ============================================================================
GRANT SELECT ON insights.weekly_reports TO nexus;
GRANT SELECT ON insights.v_weekly_health TO nexus;
GRANT SELECT ON insights.v_weekly_finance TO nexus;
GRANT SELECT ON insights.v_weekly_productivity TO nexus;
GRANT EXECUTE ON FUNCTION insights.generate_weekly_report(DATE) TO nexus;
GRANT INSERT, UPDATE ON insights.weekly_reports TO nexus;
GRANT USAGE, SELECT ON SEQUENCE insights.weekly_reports_id_seq TO nexus;
