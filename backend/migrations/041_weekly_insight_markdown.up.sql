-- Migration 041: Weekly Insight Markdown Report
-- TASK-O2: Generate deterministic, rule-based weekly reports
-- Author: Claude Coder
-- Date: 2026-01-24

-- =============================================================================
-- 1. Create improved weekly markdown generator function
-- =============================================================================

CREATE OR REPLACE FUNCTION insights.generate_weekly_markdown(p_week_start DATE DEFAULT NULL)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_week_start DATE;
    v_week_end DATE;
    v_prev_week_start DATE;
    v_markdown TEXT;

    -- Health metrics
    v_avg_recovery NUMERIC;
    v_avg_hrv NUMERIC;
    v_min_recovery NUMERIC;
    v_max_recovery NUMERIC;
    v_days_with_health INTEGER;
    v_recovery_trend TEXT;
    v_prev_avg_recovery NUMERIC;

    -- Finance metrics
    v_total_spent NUMERIC;
    v_total_income NUMERIC;
    v_net_savings NUMERIC;
    v_txn_count INTEGER;
    v_top_category TEXT;
    v_top_category_spent NUMERIC;
    v_prev_total_spent NUMERIC;
    v_spending_change_pct NUMERIC;
    v_category_breakdown TEXT;

    -- Productivity metrics
    v_total_commits INTEGER;
    v_active_days INTEGER;
    v_repos_touched INTEGER;

    -- Anomalies and insights
    v_anomaly_count INTEGER;
    v_anomaly_list TEXT;
    v_insights TEXT[];
    v_insight TEXT;

    -- Data completeness
    v_data_completeness NUMERIC;
    v_missing_sources TEXT;
BEGIN
    -- Default to last complete week (Monday-Sunday)
    IF p_week_start IS NULL THEN
        v_week_start := date_trunc('week', CURRENT_DATE - INTERVAL '7 days')::DATE;
    ELSE
        v_week_start := p_week_start;
    END IF;
    v_week_end := v_week_start + 6;
    v_prev_week_start := v_week_start - 7;

    -- ==========================================================================
    -- Gather Health Data
    -- ==========================================================================
    SELECT
        COALESCE(AVG(recovery_score), 0),
        COALESCE(AVG(hrv), 0),
        MIN(recovery_score),
        MAX(recovery_score),
        COUNT(CASE WHEN recovery_score IS NOT NULL THEN 1 END)
    INTO v_avg_recovery, v_avg_hrv, v_min_recovery, v_max_recovery, v_days_with_health
    FROM life.daily_facts
    WHERE day BETWEEN v_week_start AND v_week_end;

    -- Previous week recovery for trend
    SELECT AVG(recovery_score)
    INTO v_prev_avg_recovery
    FROM life.daily_facts
    WHERE day BETWEEN v_prev_week_start AND v_prev_week_start + 6;

    -- Determine recovery trend
    v_recovery_trend := CASE
        WHEN v_prev_avg_recovery IS NULL OR v_avg_recovery IS NULL THEN 'no_data'
        WHEN v_avg_recovery > v_prev_avg_recovery + 5 THEN 'improving'
        WHEN v_avg_recovery < v_prev_avg_recovery - 5 THEN 'declining'
        ELSE 'stable'
    END;

    -- ==========================================================================
    -- Gather Finance Data
    -- Note: In this schema, amount < 0 = expense, amount > 0 = income
    -- We use ABS() to display positive numbers for spending
    -- ==========================================================================
    SELECT
        COALESCE(SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0),
        COUNT(*)
    INTO v_total_spent, v_total_income, v_txn_count
    FROM finance.transactions
    WHERE finance.to_business_date(transaction_at) BETWEEN v_week_start AND v_week_end
      AND is_quarantined = FALSE
      AND category != 'Transfer';

    v_net_savings := v_total_income - v_total_spent;

    -- Top spending category (excludes Transfer)
    SELECT category, SUM(ABS(amount))
    INTO v_top_category, v_top_category_spent
    FROM finance.transactions
    WHERE finance.to_business_date(transaction_at) BETWEEN v_week_start AND v_week_end
      AND amount < 0
      AND is_quarantined = FALSE
      AND category != 'Transfer'
    GROUP BY category
    ORDER BY SUM(ABS(amount)) DESC
    LIMIT 1;

    -- Previous week spending for comparison
    SELECT COALESCE(SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END), 0)
    INTO v_prev_total_spent
    FROM finance.transactions
    WHERE finance.to_business_date(transaction_at) BETWEEN v_prev_week_start AND v_prev_week_start + 6
      AND is_quarantined = FALSE
      AND category != 'Transfer';

    -- Calculate spending change percentage
    IF v_prev_total_spent > 0 THEN
        v_spending_change_pct := ROUND(((v_total_spent - v_prev_total_spent) / v_prev_total_spent) * 100, 1);
    ELSE
        v_spending_change_pct := NULL;
    END IF;

    -- Category breakdown (top 5 by spending)
    SELECT STRING_AGG(
        format('  - %s: %s AED', category, ROUND(cat_total, 2)::TEXT),
        E'\n'
        ORDER BY cat_total DESC
    )
    INTO v_category_breakdown
    FROM (
        SELECT category, SUM(ABS(amount)) as cat_total
        FROM finance.transactions
        WHERE finance.to_business_date(transaction_at) BETWEEN v_week_start AND v_week_end
          AND amount < 0
          AND is_quarantined = FALSE
          AND category != 'Transfer'
        GROUP BY category
        ORDER BY SUM(ABS(amount)) DESC
        LIMIT 5
    ) top_cats;

    -- ==========================================================================
    -- Gather Productivity Data
    -- Note: Column is created_at_github, not created_at
    -- ==========================================================================
    SELECT
        COUNT(*),
        COUNT(DISTINCT (created_at_github AT TIME ZONE 'Asia/Dubai')::DATE),
        COUNT(DISTINCT repo_name)
    INTO v_total_commits, v_active_days, v_repos_touched
    FROM raw.github_events
    WHERE (created_at_github AT TIME ZONE 'Asia/Dubai')::DATE BETWEEN v_week_start AND v_week_end
      AND event_type = 'PushEvent';

    -- ==========================================================================
    -- Gather Anomalies
    -- Note: daily_anomalies is a view with 'anomalies' array column
    -- ==========================================================================
    WITH expanded_anomalies AS (
        SELECT
            day,
            UNNEST(anomalies) as anomaly_type
        FROM insights.daily_anomalies
        WHERE day BETWEEN v_week_start AND v_week_end
          AND anomalies IS NOT NULL
          AND array_length(anomalies, 1) > 0
    )
    SELECT COUNT(*), STRING_AGG(
        format('  - **%s** (%s)',
            INITCAP(REPLACE(anomaly_type, '_', ' ')),
            day::TEXT
        ),
        E'\n'
        ORDER BY day DESC
    )
    INTO v_anomaly_count, v_anomaly_list
    FROM expanded_anomalies;

    -- ==========================================================================
    -- Generate Rule-Based Insights (No LLM)
    -- ==========================================================================
    v_insights := ARRAY[]::TEXT[];

    -- Insight 1: Recovery trend
    IF v_recovery_trend = 'improving' THEN
        v_insights := v_insights || format(
            'Recovery improved this week (avg %s%% vs %s%% last week, +%s points)',
            ROUND(v_avg_recovery, 0)::TEXT,
            ROUND(v_prev_avg_recovery, 0)::TEXT,
            ROUND(v_avg_recovery - v_prev_avg_recovery, 0)::TEXT
        );
    ELSIF v_recovery_trend = 'declining' THEN
        v_insights := v_insights || format(
            'Recovery declined this week (avg %s%% vs %s%% last week, -%s points). Consider prioritizing rest.',
            ROUND(v_avg_recovery, 0)::TEXT,
            ROUND(v_prev_avg_recovery, 0)::TEXT,
            ROUND(v_prev_avg_recovery - v_avg_recovery, 0)::TEXT
        );
    END IF;

    -- Insight 2: Spending vs last week
    IF v_spending_change_pct IS NOT NULL THEN
        IF v_spending_change_pct > 20 THEN
            v_insights := v_insights || format(
                'Spending up %s%% compared to last week (%s AED vs %s AED). Top category: %s',
                v_spending_change_pct::TEXT,
                ROUND(v_total_spent, 0)::TEXT,
                ROUND(v_prev_total_spent, 0)::TEXT,
                COALESCE(v_top_category, 'N/A')
            );
        ELSIF v_spending_change_pct < -20 THEN
            v_insights := v_insights || format(
                'Spending down %s%% compared to last week (%s AED vs %s AED). Good financial discipline.',
                ABS(v_spending_change_pct)::TEXT,
                ROUND(v_total_spent, 0)::TEXT,
                ROUND(v_prev_total_spent, 0)::TEXT
            );
        END IF;
    END IF;

    -- Insight 3: High HRV variation
    IF v_max_recovery - v_min_recovery > 30 THEN
        v_insights := v_insights || format(
            'Large recovery variation this week (min %s%%, max %s%%). Sleep consistency may need attention.',
            ROUND(v_min_recovery, 0)::TEXT,
            ROUND(v_max_recovery, 0)::TEXT
        );
    END IF;

    -- Insight 4: Low recovery with spending
    IF v_avg_recovery < 50 AND v_total_spent > 1000 THEN
        v_insights := v_insights || format(
            'Low recovery week (%s%% avg) combined with %s AED spending. Rest and recovery recommended.',
            ROUND(v_avg_recovery, 0)::TEXT,
            ROUND(v_total_spent, 0)::TEXT
        );
    END IF;

    -- Insight 5: High productivity
    IF v_total_commits > 30 THEN
        v_insights := v_insights || format(
            'Productive coding week: %s commits across %s repos over %s active days.',
            v_total_commits::TEXT,
            v_repos_touched::TEXT,
            v_active_days::TEXT
        );
    END IF;

    -- ==========================================================================
    -- Calculate Data Completeness
    -- ==========================================================================
    v_data_completeness := (
        (CASE WHEN v_days_with_health > 0 THEN 33 ELSE 0 END) +
        (CASE WHEN v_txn_count > 0 THEN 33 ELSE 0 END) +
        (CASE WHEN v_total_commits > 0 THEN 34 ELSE 0 END)
    );

    v_missing_sources := '';
    IF v_days_with_health = 0 THEN
        v_missing_sources := v_missing_sources || 'WHOOP, ';
    END IF;
    IF v_txn_count = 0 THEN
        v_missing_sources := v_missing_sources || 'Finance, ';
    END IF;
    IF v_total_commits = 0 THEN
        v_missing_sources := v_missing_sources || 'GitHub, ';
    END IF;
    v_missing_sources := RTRIM(v_missing_sources, ', ');

    -- ==========================================================================
    -- Build Markdown Report
    -- ==========================================================================
    v_markdown := format(
        E'# LifeOS Weekly Insight Report\n\n' ||
        E'**Week:** %s to %s\n\n' ||
        E'**Data Completeness:** %s%%' ||
        CASE WHEN v_missing_sources != '' THEN E' (Missing: ' || v_missing_sources || E')' ELSE '' END ||
        E'\n\n---\n\n' ||

        E'## Health\n\n' ||
        E'| Metric | Value | Trend |\n' ||
        E'|--------|-------|-------|\n' ||
        E'| Avg Recovery | %s%% | %s |\n' ||
        E'| Avg HRV | %s ms | |\n' ||
        E'| Recovery Range | %s%% - %s%% | |\n' ||
        E'| Days with Data | %s/7 | |\n\n' ||

        E'## Finance\n\n' ||
        E'| Metric | This Week | vs Last Week |\n' ||
        E'|--------|-----------|---------------|\n' ||
        E'| Total Spent | %s AED | %s |\n' ||
        E'| Total Income | %s AED | |\n' ||
        E'| Net Savings | %s AED | |\n' ||
        E'| Transactions | %s | |\n\n' ||
        E'### Top Categories\n' ||
        COALESCE(v_category_breakdown, E'  - No spending recorded') || E'\n\n' ||

        E'## Productivity\n\n' ||
        E'| Metric | Value |\n' ||
        E'|--------|-------|\n' ||
        E'| Commits | %s |\n' ||
        E'| Active Days | %s |\n' ||
        E'| Repos | %s |\n\n',

        -- Substitutions
        v_week_start::TEXT,
        v_week_end::TEXT,
        v_data_completeness::TEXT,

        COALESCE(ROUND(v_avg_recovery, 0)::TEXT, 'N/A'),
        CASE v_recovery_trend
            WHEN 'improving' THEN 'improving'
            WHEN 'declining' THEN 'declining'
            WHEN 'stable' THEN 'stable'
            ELSE '-'
        END,
        COALESCE(ROUND(v_avg_hrv, 0)::TEXT, 'N/A'),
        COALESCE(ROUND(v_min_recovery, 0)::TEXT, 'N/A'),
        COALESCE(ROUND(v_max_recovery, 0)::TEXT, 'N/A'),
        v_days_with_health::TEXT,

        ROUND(v_total_spent, 2)::TEXT,
        CASE
            WHEN v_spending_change_pct IS NULL THEN 'N/A'
            WHEN v_spending_change_pct > 0 THEN '+' || v_spending_change_pct::TEXT || '%'
            ELSE v_spending_change_pct::TEXT || '%'
        END,
        ROUND(v_total_income, 2)::TEXT,
        ROUND(v_net_savings, 2)::TEXT,
        v_txn_count::TEXT,

        v_total_commits::TEXT,
        v_active_days::TEXT,
        v_repos_touched::TEXT
    );

    -- Add anomalies section
    IF v_anomaly_count > 0 THEN
        v_markdown := v_markdown || format(
            E'## Anomalies (%s detected)\n\n%s\n\n',
            v_anomaly_count::TEXT,
            v_anomaly_list
        );
    ELSE
        v_markdown := v_markdown || E'## Anomalies\n\nNo significant anomalies detected this week.\n\n';
    END IF;

    -- Add insights section
    IF array_length(v_insights, 1) > 0 THEN
        v_markdown := v_markdown || E'## Key Insights\n\n';
        FOREACH v_insight IN ARRAY v_insights LOOP
            v_markdown := v_markdown || format(E'- %s\n', v_insight);
        END LOOP;
        v_markdown := v_markdown || E'\n';
    ELSE
        v_markdown := v_markdown || E'## Key Insights\n\nNormal week - no significant patterns detected.\n\n';
    END IF;

    -- Footer
    v_markdown := v_markdown || format(
        E'---\n\n' ||
        E'*Generated: %s*\n\n' ||
        E'*Report is deterministic: same inputs produce same output.*\n',
        NOW() AT TIME ZONE 'Asia/Dubai'
    );

    RETURN v_markdown;
END;
$$;

COMMENT ON FUNCTION insights.generate_weekly_markdown(DATE) IS
'Generate a deterministic markdown weekly insight report.
Returns TEXT (markdown) for the specified week or last complete week if NULL.
Rule-based insights only - no LLM reasoning.';

-- =============================================================================
-- 2. Create function to generate and store weekly report
-- =============================================================================

CREATE OR REPLACE FUNCTION insights.store_weekly_report(p_week_start DATE DEFAULT NULL)
RETURNS TABLE (
    report_id INTEGER,
    out_week_start DATE,
    out_week_end DATE,
    markdown_preview TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_week_start DATE;
    v_week_end DATE;
    v_markdown TEXT;
    v_report_id INTEGER;
BEGIN
    -- Default to last complete week
    IF p_week_start IS NULL THEN
        v_week_start := date_trunc('week', CURRENT_DATE - INTERVAL '7 days')::DATE;
    ELSE
        v_week_start := p_week_start;
    END IF;
    v_week_end := v_week_start + 6;

    -- Generate markdown
    v_markdown := insights.generate_weekly_markdown(v_week_start);

    -- Upsert report (using table alias to avoid ambiguity)
    INSERT INTO insights.weekly_reports AS wr (
        week_start,
        week_end,
        markdown_report,
        generated_at
    ) VALUES (
        v_week_start,
        v_week_end,
        v_markdown,
        NOW()
    )
    ON CONFLICT (week_start) DO UPDATE SET
        markdown_report = EXCLUDED.markdown_report,
        generated_at = NOW()
    RETURNING wr.id INTO v_report_id;

    RETURN QUERY SELECT
        v_report_id,
        v_week_start,
        v_week_end,
        LEFT(v_markdown, 200) || '...' AS markdown_preview;
END;
$$;

COMMENT ON FUNCTION insights.store_weekly_report(DATE) IS
'Generate and store weekly report markdown. Returns report ID and preview.';

-- =============================================================================
-- 3. Create convenience view for latest report
-- =============================================================================

CREATE OR REPLACE VIEW insights.v_latest_weekly_report AS
SELECT
    id,
    week_start,
    week_end,
    markdown_report,
    generated_at,
    (NOW() - generated_at) AS report_age
FROM insights.weekly_reports
ORDER BY week_start DESC
LIMIT 1;

COMMENT ON VIEW insights.v_latest_weekly_report IS
'Quick access to the most recent weekly report.';

-- =============================================================================
-- 4. Create function to get report as JSON (for API)
-- =============================================================================

CREATE OR REPLACE FUNCTION insights.get_weekly_report_json(p_week_start DATE DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_week_start DATE;
    v_week_end DATE;
    v_markdown TEXT;
    v_report RECORD;
BEGIN
    -- Default to last complete week
    IF p_week_start IS NULL THEN
        v_week_start := date_trunc('week', CURRENT_DATE - INTERVAL '7 days')::DATE;
    ELSE
        v_week_start := p_week_start;
    END IF;
    v_week_end := v_week_start + 6;

    -- Check if report exists in cache
    SELECT * INTO v_report
    FROM insights.weekly_reports
    WHERE week_start = v_week_start;

    -- Generate fresh if not cached or stale (older than 1 hour for current week)
    IF v_report IS NULL OR (
        v_week_end >= CURRENT_DATE - 1 AND
        v_report.generated_at < NOW() - INTERVAL '1 hour'
    ) THEN
        v_markdown := insights.generate_weekly_markdown(v_week_start);
    ELSE
        v_markdown := v_report.markdown_report;
    END IF;

    RETURN jsonb_build_object(
        'week_start', v_week_start,
        'week_end', v_week_end,
        'markdown_report', v_markdown,
        'generated_at', COALESCE(v_report.generated_at, NOW()),
        'is_cached', v_report IS NOT NULL
    );
END;
$$;

COMMENT ON FUNCTION insights.get_weekly_report_json(DATE) IS
'Get weekly report as JSON. Uses cache if available, generates fresh otherwise.';

-- =============================================================================
-- Done
-- =============================================================================

-- Grant permissions
GRANT EXECUTE ON FUNCTION insights.generate_weekly_markdown(DATE) TO nexus;
GRANT EXECUTE ON FUNCTION insights.store_weekly_report(DATE) TO nexus;
GRANT EXECUTE ON FUNCTION insights.get_weekly_report_json(DATE) TO nexus;
GRANT SELECT ON insights.v_latest_weekly_report TO nexus;
