-- Migration 112 DOWN: Revert to original generate_weekly_markdown without calendar/reminders

CREATE OR REPLACE FUNCTION insights.generate_weekly_markdown(p_week_start date DEFAULT NULL::date)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_week_start DATE;
    v_week_end DATE;
    v_prev_week_start DATE;

    v_avg_recovery NUMERIC;
    v_avg_hrv NUMERIC;
    v_min_recovery INT;
    v_max_recovery INT;
    v_health_days INT;

    v_total_spent NUMERIC;
    v_total_income NUMERIC;
    v_net_savings NUMERIC;
    v_txn_count INTEGER;
    v_top_categories TEXT;
    v_prev_spent NUMERIC;
    v_spend_vs_prev TEXT;

    v_total_commits INT;
    v_active_days INT;
    v_repos_touched INT;

    v_key_insights TEXT;
    v_report TEXT;
BEGIN
    v_week_start := COALESCE(p_week_start, date_trunc('week', CURRENT_DATE)::DATE);
    v_week_end := v_week_start + 6;
    v_prev_week_start := v_week_start - 7;

    -- Health
    SELECT ROUND(AVG(recovery_score)), ROUND(AVG(hrv)), MIN(recovery_score), MAX(recovery_score),
           COUNT(*) FILTER (WHERE recovery_score IS NOT NULL)
    INTO v_avg_recovery, v_avg_hrv, v_min_recovery, v_max_recovery, v_health_days
    FROM life.daily_facts WHERE day BETWEEN v_week_start AND v_week_end;

    -- Finance (canonical)
    SELECT COALESCE(SUM(expense_aed), 0), COALESCE(SUM(income_aed), 0), COALESCE(SUM(transaction_count), 0)
    INTO v_total_spent, v_total_income, v_txn_count
    FROM finance.daily_totals_aed WHERE day BETWEEN v_week_start AND v_week_end;

    v_net_savings := v_total_income - v_total_spent;

    SELECT COALESCE(SUM(expense_aed), 0) INTO v_prev_spent
    FROM finance.daily_totals_aed WHERE day BETWEEN v_prev_week_start AND v_prev_week_start + 6;

    v_spend_vs_prev := CASE WHEN v_prev_spent > 0
        THEN ROUND((v_total_spent - v_prev_spent) / v_prev_spent * 100) || '%' ELSE 'N/A' END;

    -- Top categories
    SELECT string_agg(category || ': ' || ROUND(spent, 2) || ' AED', E'\n  - ')
    INTO v_top_categories
    FROM (SELECT category, SUM(canonical_amount) as spent
          FROM finance.canonical_transactions
          WHERE transaction_date BETWEEN v_week_start AND v_week_end
            AND direction = 'expense' AND is_base_currency AND NOT exclude_from_totals
          GROUP BY category ORDER BY spent DESC LIMIT 5) sub;

    -- Productivity
    SELECT COUNT(*), COUNT(DISTINCT DATE(created_at_github)), COUNT(DISTINCT repo_name)
    INTO v_total_commits, v_active_days, v_repos_touched
    FROM raw.github_events WHERE event_type = 'PushEvent'
      AND created_at_github BETWEEN v_week_start AND v_week_end + 1;

    -- Insights
    v_key_insights := '';
    IF v_max_recovery IS NOT NULL AND v_min_recovery IS NOT NULL AND v_max_recovery - v_min_recovery > 30 THEN
        v_key_insights := v_key_insights || '- Recovery varied widely (' || v_min_recovery || '% to ' || v_max_recovery || '%)' || E'\n';
    END IF;
    IF v_total_spent > 0 AND v_prev_spent > 0 AND v_total_spent > v_prev_spent * 1.5 THEN
        v_key_insights := v_key_insights || '- Spending up ' || v_spend_vs_prev || ' from last week' || E'\n';
    END IF;
    IF v_key_insights = '' THEN v_key_insights := '- No significant patterns detected'; END IF;

    v_report := format(
        E'# LifeOS Weekly Report\n\n**Week:** %s to %s\n\n---\n\n' ||
        E'## Health\n| Metric | Value |\n|--------|-------|\n' ||
        E'| Avg Recovery | %s%% |\n| Avg HRV | %s ms |\n| Range | %s%% - %s%% |\n| Days | %s/7 |\n\n' ||
        E'## Finance\n| Metric | Value | vs Last Week |\n|--------|-------|---------------|\n' ||
        E'| Spent | %s AED | %s |\n| Income | %s AED | |\n| Net | %s AED | |\n| Txns | %s | |\n\n' ||
        E'### Top Categories\n  - %s\n\n' ||
        E'## Productivity\nCommits: %s | Active Days: %s | Repos: %s\n\n' ||
        E'## Insights\n%s\n\n---\n*Generated: %s*\n',
        v_week_start, v_week_end,
        COALESCE(v_avg_recovery::TEXT, 'N/A'), COALESCE(v_avg_hrv::TEXT, 'N/A'),
        COALESCE(v_min_recovery::TEXT, '-'), COALESCE(v_max_recovery::TEXT, '-'), v_health_days,
        ROUND(v_total_spent, 2), v_spend_vs_prev, ROUND(v_total_income, 2), ROUND(v_net_savings, 2), v_txn_count,
        COALESCE(v_top_categories, 'None'),
        v_total_commits, v_active_days, v_repos_touched,
        v_key_insights, NOW()
    );

    RETURN v_report;
END;
$function$;
