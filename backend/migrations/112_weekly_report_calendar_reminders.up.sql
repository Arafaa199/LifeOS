-- Migration 112: Add Calendar + Reminders section to weekly insights email
-- Rewrites insights.generate_weekly_markdown() to include:
--   - Calendar section: total meetings, total hours, busiest day
--   - Reminders section: due, completed, overdue, completion rate

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

    -- Calendar variables
    v_meeting_count INT;
    v_meeting_hours NUMERIC;
    v_busiest_day TEXT;
    v_busiest_day_count INT;
    v_calendar_section TEXT;

    -- Reminder variables
    v_reminders_due INT;
    v_reminders_completed INT;
    v_reminders_overdue INT;
    v_reminder_rate NUMERIC;
    v_reminder_section TEXT;

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

    -- Calendar
    SELECT COALESCE(SUM(meeting_count), 0),
           COALESCE(SUM(meeting_hours), 0)
    INTO v_meeting_count, v_meeting_hours
    FROM life.v_daily_calendar_summary
    WHERE day BETWEEN v_week_start AND v_week_end;

    -- Busiest calendar day
    SELECT to_char(day, 'Dy DD Mon'), meeting_count
    INTO v_busiest_day, v_busiest_day_count
    FROM life.v_daily_calendar_summary
    WHERE day BETWEEN v_week_start AND v_week_end
    ORDER BY meeting_count DESC, meeting_hours DESC NULLS LAST
    LIMIT 1;

    IF v_meeting_count > 0 THEN
        v_calendar_section := format(
            E'## Calendar\n| Metric | Value |\n|--------|-------|\n' ||
            E'| Meetings | %s |\n| Total Hours | %s |\n| Busiest Day | %s (%s meetings) |\n\n',
            v_meeting_count,
            ROUND(v_meeting_hours, 1),
            COALESCE(v_busiest_day, '-'),
            COALESCE(v_busiest_day_count::TEXT, '0')
        );
    ELSE
        v_calendar_section := E'## Calendar\nNo meetings this week.\n\n';
    END IF;

    -- Reminders
    SELECT COALESCE(SUM(reminders_due), 0),
           COALESCE(SUM(reminders_completed), 0),
           COALESCE(SUM(reminders_overdue), 0)
    INTO v_reminders_due, v_reminders_completed, v_reminders_overdue
    FROM life.v_daily_reminder_summary
    WHERE day BETWEEN v_week_start AND v_week_end;

    v_reminder_rate := CASE WHEN v_reminders_due > 0
        THEN ROUND(v_reminders_completed::NUMERIC / v_reminders_due * 100, 1)
        ELSE 0 END;

    IF v_reminders_due > 0 THEN
        v_reminder_section := format(
            E'## Reminders\n| Metric | Value |\n|--------|-------|\n' ||
            E'| Due | %s |\n| Completed | %s |\n| Overdue | %s |\n| Completion Rate | %s%% |\n\n',
            v_reminders_due, v_reminders_completed, v_reminders_overdue, v_reminder_rate
        );
    ELSE
        v_reminder_section := E'## Reminders\nNo reminders due this week.\n\n';
    END IF;

    -- Insights
    v_key_insights := '';
    IF v_max_recovery IS NOT NULL AND v_min_recovery IS NOT NULL AND v_max_recovery - v_min_recovery > 30 THEN
        v_key_insights := v_key_insights || '- Recovery varied widely (' || v_min_recovery || '% to ' || v_max_recovery || '%)' || E'\n';
    END IF;
    IF v_total_spent > 0 AND v_prev_spent > 0 AND v_total_spent > v_prev_spent * 1.5 THEN
        v_key_insights := v_key_insights || '- Spending up ' || v_spend_vs_prev || ' from last week' || E'\n';
    END IF;
    IF v_meeting_count > 0 AND v_meeting_hours > 10 THEN
        v_key_insights := v_key_insights || '- Heavy meeting week: ' || ROUND(v_meeting_hours, 1) || ' hours across ' || v_meeting_count || ' meetings' || E'\n';
    END IF;
    IF v_reminders_due > 0 AND v_reminder_rate < 50 THEN
        v_key_insights := v_key_insights || '- Low task completion: only ' || v_reminder_rate || '% of reminders completed' || E'\n';
    END IF;
    IF v_key_insights = '' THEN v_key_insights := '- No significant patterns detected'; END IF;

    v_report := format(
        E'# LifeOS Weekly Report\n\n**Week:** %s to %s\n\n---\n\n' ||
        E'## Health\n| Metric | Value |\n|--------|-------|\n' ||
        E'| Avg Recovery | %s%% |\n| Avg HRV | %s ms |\n| Range | %s%% - %s%% |\n| Days | %s/7 |\n\n' ||
        E'## Finance\n| Metric | Value | vs Last Week |\n|--------|-------|---------------|\n' ||
        E'| Spent | %s AED | %s |\n| Income | %s AED | |\n| Net | %s AED | |\n| Txns | %s | |\n\n' ||
        E'### Top Categories\n  - %s\n\n' ||
        E'%s' ||  -- Calendar section
        E'%s' ||  -- Reminders section
        E'## Productivity\nCommits: %s | Active Days: %s | Repos: %s\n\n' ||
        E'## Insights\n%s\n\n---\n*Generated: %s*\n',
        v_week_start, v_week_end,
        COALESCE(v_avg_recovery::TEXT, 'N/A'), COALESCE(v_avg_hrv::TEXT, 'N/A'),
        COALESCE(v_min_recovery::TEXT, '-'), COALESCE(v_max_recovery::TEXT, '-'), v_health_days,
        ROUND(v_total_spent, 2), v_spend_vs_prev, ROUND(v_total_income, 2), ROUND(v_net_savings, 2), v_txn_count,
        COALESCE(v_top_categories, 'None'),
        v_calendar_section,
        v_reminder_section,
        v_total_commits, v_active_days, v_repos_touched,
        v_key_insights, NOW()
    );

    RETURN v_report;
END;
$function$;
