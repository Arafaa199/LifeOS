-- Migration 110: Calendar + Productivity Correlation Views
-- TASK-FEAT.7: Correlate meeting hours with recovery, GitHub activity, and spending
-- Answers: "Do heavy meeting days affect my recovery or productivity?"

BEGIN;

-- 1. Core daily correlation view joining calendar + health + productivity + finance
DROP VIEW IF EXISTS insights.calendar_productivity_correlation CASCADE;
CREATE VIEW insights.calendar_productivity_correlation AS
SELECT
    c.day,
    c.meeting_count,
    c.meeting_hours,
    f.recovery_score,
    f.sleep_hours,
    f.hrv,
    f.strain,
    f.spend_total,
    f.transaction_count,
    COALESCE(p.push_events, 0)   AS github_push_events,
    COALESCE(p.pr_events, 0)     AS github_pr_events,
    COALESCE(p.repos_touched, 0) AS github_repos_touched,
    COALESCE(p.productivity_score, 0) AS github_productivity_score,
    -- Previous night's sleep (day - 1 sleep affects today's performance)
    prev.sleep_hours AS sleep_hours_prev_night,
    prev.recovery_score AS recovery_score_morning,
    -- Next day impact (does a heavy meeting day hurt tomorrow?)
    nxt.recovery_score AS next_day_recovery,
    nxt.sleep_hours AS next_day_sleep_hours,
    -- Meeting intensity classification
    CASE
        WHEN c.meeting_hours > 4 THEN 'very_heavy'
        WHEN c.meeting_hours > 2 THEN 'heavy'
        WHEN c.meeting_hours > 0 THEN 'light'
        ELSE 'none'
    END AS meeting_intensity
FROM life.v_daily_calendar_summary c
LEFT JOIN life.daily_facts f ON f.day = c.day
LEFT JOIN life.daily_facts prev ON prev.day = c.day - 1
LEFT JOIN life.daily_facts nxt ON nxt.day = c.day + 1
LEFT JOIN life.daily_productivity p ON p.day = c.day
WHERE c.day >= (CURRENT_DATE - INTERVAL '90 days')
ORDER BY c.day DESC;

-- 2. Pattern summary function: compare heavy vs light meeting days
DROP FUNCTION IF EXISTS insights.calendar_pattern_summary();
CREATE FUNCTION insights.calendar_pattern_summary()
RETURNS TABLE (
    metric TEXT,
    heavy_meeting_days_avg NUMERIC,
    light_meeting_days_avg NUMERIC,
    no_meeting_days_avg NUMERIC,
    heavy_sample_count BIGINT,
    light_sample_count BIGINT,
    no_meeting_sample_count BIGINT,
    finding TEXT
) LANGUAGE sql STABLE AS $$
    WITH categorized AS (
        SELECT
            meeting_intensity,
            recovery_score,
            next_day_recovery,
            sleep_hours,
            next_day_sleep_hours,
            spend_total,
            github_productivity_score
        FROM insights.calendar_productivity_correlation
        WHERE meeting_hours IS NOT NULL
    ),
    agg AS (
        SELECT
            meeting_intensity,
            COUNT(*) AS n,
            ROUND(AVG(recovery_score), 1) AS avg_recovery,
            ROUND(AVG(next_day_recovery), 1) AS avg_next_recovery,
            ROUND(AVG(sleep_hours), 2) AS avg_sleep,
            ROUND(AVG(next_day_sleep_hours), 2) AS avg_next_sleep,
            ROUND(AVG(spend_total), 0) AS avg_spend,
            ROUND(AVG(github_productivity_score), 1) AS avg_github
        FROM categorized
        GROUP BY meeting_intensity
    ),
    heavy AS (SELECT * FROM agg WHERE meeting_intensity IN ('heavy', 'very_heavy')),
    light AS (SELECT * FROM agg WHERE meeting_intensity = 'light'),
    none AS (SELECT * FROM agg WHERE meeting_intensity = 'none')
    -- Recovery on meeting day
    SELECT
        'same_day_recovery'::TEXT AS metric,
        (SELECT avg_recovery FROM heavy),
        (SELECT avg_recovery FROM light),
        (SELECT avg_recovery FROM none),
        (SELECT COALESCE(SUM(n), 0) FROM heavy),
        (SELECT COALESCE(n, 0) FROM light),
        (SELECT COALESCE(n, 0) FROM none),
        CASE
            WHEN (SELECT COALESCE(SUM(n), 0) FROM heavy) < 3 OR (SELECT COALESCE(n, 0) FROM light) < 3
            THEN 'Insufficient data for recovery comparison'
            WHEN (SELECT avg_recovery FROM heavy) < (SELECT avg_recovery FROM light) - 10
            THEN 'Heavy meeting days show lower recovery (avg ' || (SELECT avg_recovery FROM heavy) || ' vs ' || (SELECT avg_recovery FROM light) || ')'
            WHEN (SELECT avg_recovery FROM heavy) > (SELECT avg_recovery FROM light) + 10
            THEN 'Heavy meeting days show higher recovery (avg ' || (SELECT avg_recovery FROM heavy) || ' vs ' || (SELECT avg_recovery FROM light) || ')'
            ELSE 'No significant recovery difference between heavy and light meeting days'
        END
    UNION ALL
    -- Next-day recovery (meeting fatigue effect)
    SELECT
        'next_day_recovery'::TEXT,
        (SELECT avg_next_recovery FROM heavy),
        (SELECT avg_next_recovery FROM light),
        (SELECT avg_next_recovery FROM none),
        (SELECT COALESCE(SUM(n), 0) FROM heavy),
        (SELECT COALESCE(n, 0) FROM light),
        (SELECT COALESCE(n, 0) FROM none),
        CASE
            WHEN (SELECT COALESCE(SUM(n), 0) FROM heavy) < 3 OR (SELECT COALESCE(n, 0) FROM light) < 3
            THEN 'Insufficient data for next-day recovery comparison'
            WHEN (SELECT avg_next_recovery FROM heavy) < (SELECT avg_next_recovery FROM light) - 10
            THEN 'Recovery drops after heavy meeting days (next-day avg ' || (SELECT avg_next_recovery FROM heavy) || ' vs ' || (SELECT avg_next_recovery FROM light) || ')'
            WHEN (SELECT avg_next_recovery FROM heavy) > (SELECT avg_next_recovery FROM light) + 10
            THEN 'Recovery improves after heavy meeting days (next-day avg ' || (SELECT avg_next_recovery FROM heavy) || ' vs ' || (SELECT avg_next_recovery FROM light) || ')'
            ELSE 'No significant next-day recovery impact from heavy meetings'
        END
    UNION ALL
    -- Spending on meeting days
    SELECT
        'same_day_spending'::TEXT,
        (SELECT avg_spend FROM heavy),
        (SELECT avg_spend FROM light),
        (SELECT avg_spend FROM none),
        (SELECT COALESCE(SUM(n), 0) FROM heavy),
        (SELECT COALESCE(n, 0) FROM light),
        (SELECT COALESCE(n, 0) FROM none),
        CASE
            WHEN (SELECT COALESCE(SUM(n), 0) FROM heavy) < 3 OR (SELECT COALESCE(n, 0) FROM light) < 3
            THEN 'Insufficient data for spending comparison'
            WHEN COALESCE((SELECT avg_spend FROM heavy), 0) > COALESCE((SELECT avg_spend FROM light), 0) * 1.5
            THEN 'Spending is higher on heavy meeting days (avg ' || COALESCE((SELECT avg_spend FROM heavy), 0) || ' vs ' || COALESCE((SELECT avg_spend FROM light), 0) || ' AED)'
            ELSE 'No significant spending difference on meeting days'
        END
    UNION ALL
    -- GitHub productivity on meeting days
    SELECT
        'github_productivity'::TEXT,
        (SELECT avg_github FROM heavy),
        (SELECT avg_github FROM light),
        (SELECT avg_github FROM none),
        (SELECT COALESCE(SUM(n), 0) FROM heavy),
        (SELECT COALESCE(n, 0) FROM light),
        (SELECT COALESCE(n, 0) FROM none),
        CASE
            WHEN (SELECT COALESCE(SUM(n), 0) FROM heavy) < 3 OR (SELECT COALESCE(n, 0) FROM light) < 3
            THEN 'Insufficient data for productivity comparison'
            WHEN COALESCE((SELECT avg_github FROM heavy), 0) < COALESCE((SELECT avg_github FROM light), 0) * 0.5
            THEN 'GitHub productivity drops on heavy meeting days (avg ' || COALESCE((SELECT avg_github FROM heavy), 0) || ' vs ' || COALESCE((SELECT avg_github FROM light), 0) || ')'
            ELSE 'No significant GitHub productivity difference on meeting days'
        END;
$$;

-- 3. Fix existing meetings_hrv_correlation to actually use calendar data
DROP VIEW IF EXISTS insights.meetings_hrv_correlation CASCADE;
CREATE VIEW insights.meetings_hrv_correlation AS
SELECT
    c.day,
    c.meeting_count,
    c.meeting_hours,
    f.hrv,
    LEAD(f.hrv) OVER (ORDER BY c.day) AS next_day_hrv,
    f.recovery_score,
    LEAD(f.recovery_score) OVER (ORDER BY c.day) AS next_day_recovery
FROM life.v_daily_calendar_summary c
LEFT JOIN life.daily_facts f ON f.day = c.day
WHERE c.day >= (CURRENT_DATE - INTERVAL '90 days')
ORDER BY c.day DESC;

COMMIT;
