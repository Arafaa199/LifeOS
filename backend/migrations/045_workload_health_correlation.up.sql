-- Migration: 045_workload_health_correlation.up.sql
-- Task: TASK-C3 - Workload (GitHub + Calendar) vs Health Correlation
-- Created: 2026-01-24
-- Purpose: Answer "Does heavy work hurt recovery?"

-- ============================================================================
-- insights.workload_daily: Daily workload metrics with next-day health
-- ============================================================================
-- Links each day's workload to the NEXT day's recovery/health
-- (workload impact manifests the following day)

CREATE OR REPLACE VIEW insights.workload_daily AS
WITH daily_workload AS (
    SELECT
        day,
        commits,
        push_events,
        pr_events,
        issue_events,
        repos_touched,
        productivity_score,
        -- Workload calculation: weighted sum of activities
        -- Commits and PRs weighted higher as they represent more effort
        COALESCE(push_events, 0) * 2 +
        COALESCE(pr_events, 0) * 3 +
        COALESCE(issue_events, 0) * 1 +
        COALESCE(repos_touched, 0) * 1 AS workload_score,
        -- When calendar is available, add meeting_hours here
        0 AS meeting_hours  -- Placeholder for future calendar integration
    FROM life.daily_productivity
),
next_day_health AS (
    SELECT
        day,
        recovery_score,
        hrv,
        ROUND(sleep_minutes / 60.0, 2) AS sleep_hours,
        rhr,
        strain
    FROM life.daily_facts
    WHERE recovery_score IS NOT NULL
)
SELECT
    w.day,
    w.push_events,
    w.pr_events,
    w.issue_events,
    w.repos_touched,
    w.productivity_score,
    w.workload_score,
    w.meeting_hours,
    -- Workload bucket based on workload_score
    CASE
        WHEN w.workload_score >= 20 THEN 'heavy'
        WHEN w.workload_score >= 8 THEN 'moderate'
        ELSE 'light'
    END AS workload_bucket,
    -- Next day's health metrics
    h.recovery_score AS next_day_recovery,
    h.hrv AS next_day_hrv,
    h.sleep_hours AS next_day_sleep,
    h.rhr AS next_day_rhr,
    h.strain AS next_day_strain
FROM daily_workload w
LEFT JOIN next_day_health h ON h.day = w.day + 1
WHERE w.day >= CURRENT_DATE - 90;  -- Last 90 days

COMMENT ON VIEW insights.workload_daily IS
'Daily workload metrics (GitHub activity) linked to next-day health outcomes';

-- ============================================================================
-- insights.workload_health_correlation: Aggregated by workload bucket
-- ============================================================================
-- Shows avg recovery, HRV, sleep per workload level with statistical indicators

CREATE OR REPLACE VIEW insights.workload_health_correlation AS
WITH bucket_stats AS (
    SELECT
        workload_bucket,
        COUNT(*) AS sample_count,
        ROUND(AVG(workload_score)::NUMERIC, 1) AS avg_workload_score,
        ROUND(AVG(next_day_recovery)::NUMERIC, 1) AS avg_recovery,
        ROUND(AVG(next_day_hrv)::NUMERIC, 1) AS avg_hrv,
        ROUND(AVG(next_day_sleep)::NUMERIC, 2) AS avg_sleep_hours,
        ROUND(AVG(next_day_rhr)::NUMERIC, 1) AS avg_rhr,
        ROUND(STDDEV(next_day_recovery)::NUMERIC, 1) AS stddev_recovery
    FROM insights.workload_daily
    WHERE next_day_recovery IS NOT NULL
    GROUP BY workload_bucket
),
overall_stats AS (
    SELECT
        AVG(next_day_recovery) AS overall_avg_recovery,
        STDDEV(next_day_recovery) AS overall_stddev_recovery
    FROM insights.workload_daily
    WHERE next_day_recovery IS NOT NULL
)
SELECT
    bs.workload_bucket,
    bs.sample_count,
    bs.avg_workload_score,
    bs.avg_recovery,
    bs.avg_hrv,
    bs.avg_sleep_hours,
    bs.avg_rhr,
    -- Z-score: how far is this bucket's recovery from overall mean?
    CASE
        WHEN os.overall_stddev_recovery > 0
        THEN ROUND(((bs.avg_recovery - os.overall_avg_recovery) / os.overall_stddev_recovery)::NUMERIC, 2)
        ELSE 0
    END AS z_score,
    -- Significance level
    CASE
        WHEN bs.sample_count < 5 THEN 'insufficient_data'
        WHEN bs.sample_count < 10 THEN 'low_confidence'
        WHEN ABS((bs.avg_recovery - os.overall_avg_recovery) / NULLIF(os.overall_stddev_recovery, 0)) >= 2 THEN 'significant'
        WHEN ABS((bs.avg_recovery - os.overall_avg_recovery) / NULLIF(os.overall_stddev_recovery, 0)) >= 1 THEN 'notable'
        ELSE 'within_normal'
    END AS significance
FROM bucket_stats bs
CROSS JOIN overall_stats os
ORDER BY
    CASE bs.workload_bucket
        WHEN 'light' THEN 1
        WHEN 'moderate' THEN 2
        WHEN 'heavy' THEN 3
    END;

COMMENT ON VIEW insights.workload_health_correlation IS
'Aggregated health metrics by workload bucket (light/moderate/heavy) with statistical significance';

-- ============================================================================
-- insights.workload_health_correlation_stats: Pearson correlation
-- ============================================================================
-- Calculates correlation coefficient between workload and recovery

CREATE OR REPLACE VIEW insights.workload_health_correlation_stats AS
WITH paired_data AS (
    SELECT
        workload_score,
        next_day_recovery
    FROM insights.workload_daily
    WHERE next_day_recovery IS NOT NULL
      AND workload_score > 0  -- Only include days with actual work
),
stats AS (
    SELECT
        COUNT(*) AS n,
        AVG(workload_score) AS avg_workload,
        AVG(next_day_recovery) AS avg_recovery,
        STDDEV(workload_score) AS stddev_workload,
        STDDEV(next_day_recovery) AS stddev_recovery,
        SUM((workload_score - (SELECT AVG(workload_score) FROM paired_data)) *
            (next_day_recovery - (SELECT AVG(next_day_recovery) FROM paired_data))) AS covariance_sum
    FROM paired_data
),
correlation AS (
    SELECT
        n,
        ROUND(avg_workload::NUMERIC, 1) AS avg_workload,
        ROUND(avg_recovery::NUMERIC, 1) AS avg_recovery,
        CASE
            WHEN stddev_workload > 0 AND stddev_recovery > 0 AND n > 1
            THEN ROUND((covariance_sum / (n - 1) / (stddev_workload * stddev_recovery))::NUMERIC, 3)
            ELSE 0
        END AS correlation_coefficient
    FROM stats
)
SELECT
    n AS sample_count,
    avg_workload,
    avg_recovery,
    correlation_coefficient,
    -- Interpret correlation strength
    CASE
        WHEN n < 10 THEN 'insufficient_data'
        WHEN ABS(correlation_coefficient) >= 0.7 THEN 'strong'
        WHEN ABS(correlation_coefficient) >= 0.4 THEN 'moderate'
        WHEN ABS(correlation_coefficient) >= 0.2 THEN 'weak'
        ELSE 'negligible'
    END AS correlation_strength,
    -- Direction
    CASE
        WHEN n < 10 THEN NULL
        WHEN correlation_coefficient > 0.1 THEN 'positive'
        WHEN correlation_coefficient < -0.1 THEN 'negative'
        ELSE 'none'
    END AS correlation_direction,
    -- Plain English finding
    CASE
        WHEN n < 10 THEN 'Insufficient data (need 10+ days with workload and next-day health data)'
        WHEN correlation_coefficient < -0.3 THEN
            'Heavy work days show reduced next-day recovery (r=' || correlation_coefficient || ')'
        WHEN correlation_coefficient > 0.3 THEN
            'Active work days show improved next-day recovery (r=' || correlation_coefficient || ')'
        ELSE
            'No clear relationship between workload and next-day recovery'
    END AS finding
FROM correlation;

COMMENT ON VIEW insights.workload_health_correlation_stats IS
'Pearson correlation coefficient between workload score and next-day recovery';

-- ============================================================================
-- insights.workload_health_summary: Dashboard-ready summary
-- ============================================================================

CREATE OR REPLACE VIEW insights.workload_health_summary AS
WITH bucket_data AS (
    SELECT * FROM insights.workload_health_correlation
),
correlation_data AS (
    SELECT * FROM insights.workload_health_correlation_stats
)
SELECT
    (SELECT COUNT(*) FROM insights.workload_daily WHERE next_day_recovery IS NOT NULL) AS days_analyzed,
    (SELECT correlation_coefficient FROM correlation_data) AS correlation_coefficient,
    (SELECT correlation_strength FROM correlation_data) AS correlation_strength,
    (SELECT correlation_direction FROM correlation_data) AS correlation_direction,
    (SELECT finding FROM correlation_data) AS finding,
    -- Recovery by workload level
    (SELECT avg_recovery FROM bucket_data WHERE workload_bucket = 'light') AS light_workload_avg_recovery,
    (SELECT avg_recovery FROM bucket_data WHERE workload_bucket = 'moderate') AS moderate_workload_avg_recovery,
    (SELECT avg_recovery FROM bucket_data WHERE workload_bucket = 'heavy') AS heavy_workload_avg_recovery,
    -- Recovery difference (heavy vs light)
    CASE
        WHEN (SELECT avg_recovery FROM bucket_data WHERE workload_bucket = 'light') IS NOT NULL
         AND (SELECT avg_recovery FROM bucket_data WHERE workload_bucket = 'heavy') IS NOT NULL
        THEN ROUND((
            (SELECT avg_recovery FROM bucket_data WHERE workload_bucket = 'heavy') -
            (SELECT avg_recovery FROM bucket_data WHERE workload_bucket = 'light')
        )::NUMERIC, 1)
        ELSE NULL
    END AS heavy_vs_light_recovery_diff;

COMMENT ON VIEW insights.workload_health_summary IS
'Dashboard-ready summary of workload vs health correlation';
