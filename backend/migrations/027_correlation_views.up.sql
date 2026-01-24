-- Migration: 027_correlation_views
-- Adds cross-domain correlation views for insights
-- TASK-064: Cross-Domain Correlation Views

-- ============================================================================
-- insights schema for correlation analysis
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS insights;

-- ============================================================================
-- insights.sleep_recovery_correlation
-- Does better sleep predict better next-day recovery?
-- ============================================================================

CREATE OR REPLACE VIEW insights.sleep_recovery_correlation AS
WITH sleep_data AS (
    SELECT
        day,
        sleep_hours,
        deep_sleep_hours,
        sleep_efficiency,
        sleep_performance,
        LEAD(recovery_score) OVER (ORDER BY day) AS next_day_recovery,
        LEAD(hrv) OVER (ORDER BY day) AS next_day_hrv
    FROM life.daily_facts
    WHERE sleep_hours IS NOT NULL
)
SELECT
    day,
    sleep_hours,
    deep_sleep_hours,
    sleep_efficiency,
    next_day_recovery,
    next_day_hrv,
    CASE
        WHEN sleep_hours >= 7 AND next_day_recovery >= 70 THEN 'good_sleep_good_recovery'
        WHEN sleep_hours >= 7 AND next_day_recovery < 70 THEN 'good_sleep_poor_recovery'
        WHEN sleep_hours < 7 AND next_day_recovery >= 70 THEN 'poor_sleep_good_recovery'
        ELSE 'poor_sleep_poor_recovery'
    END AS pattern
FROM sleep_data
WHERE next_day_recovery IS NOT NULL
ORDER BY day DESC;

-- ============================================================================
-- insights.spending_recovery_correlation
-- Do you spend more when feeling good (or stressed)?
-- ============================================================================

CREATE OR REPLACE VIEW insights.spending_recovery_correlation AS
SELECT
    day,
    recovery_score,
    spend_total,
    transaction_count,
    CASE
        WHEN recovery_score >= 70 THEN 'high_recovery'
        WHEN recovery_score >= 40 THEN 'medium_recovery'
        ELSE 'low_recovery'
    END AS recovery_bucket,
    CASE
        WHEN spend_total > (SELECT AVG(spend_total) * 1.5 FROM life.daily_facts WHERE spend_total > 0) THEN 'high_spend'
        WHEN spend_total > 0 THEN 'normal_spend'
        ELSE 'no_spend'
    END AS spend_bucket
FROM life.daily_facts
WHERE recovery_score IS NOT NULL
  AND day >= NOW() - INTERVAL '90 days'
ORDER BY day DESC;

-- Aggregate view for analysis
CREATE OR REPLACE VIEW insights.spending_by_recovery_level AS
SELECT
    CASE
        WHEN recovery_score >= 70 THEN 'high_recovery'
        WHEN recovery_score >= 40 THEN 'medium_recovery'
        ELSE 'low_recovery'
    END AS recovery_level,
    COUNT(*) AS days,
    ROUND(AVG(spend_total)::numeric, 2) AS avg_spend,
    ROUND(AVG(transaction_count)::numeric, 1) AS avg_transactions,
    ROUND(STDDEV(spend_total)::numeric, 2) AS spend_stddev
FROM life.daily_facts
WHERE recovery_score IS NOT NULL
  AND day >= NOW() - INTERVAL '90 days'
GROUP BY 1
ORDER BY avg_spend DESC;

-- ============================================================================
-- insights.meetings_hrv_correlation
-- Does heavy meeting load affect next-day HRV?
-- (Placeholder - will be populated once calendar data is available)
-- ============================================================================

CREATE OR REPLACE VIEW insights.meetings_hrv_correlation AS
SELECT
    lf.day,
    -- Placeholder for meeting data (will come from iOS calendar sync)
    NULL::integer AS meeting_count,
    NULL::numeric AS meeting_hours,
    lf.hrv,
    LEAD(lf.hrv) OVER (ORDER BY lf.day) AS next_day_hrv,
    lf.recovery_score,
    LEAD(lf.recovery_score) OVER (ORDER BY lf.day) AS next_day_recovery
FROM life.daily_facts lf
WHERE lf.day >= NOW() - INTERVAL '90 days'
ORDER BY lf.day DESC;

-- ============================================================================
-- insights.screen_sleep_correlation
-- Does TV watching in the evening correlate with sleep quality?
-- ============================================================================

CREATE OR REPLACE VIEW insights.screen_sleep_correlation AS
WITH tv_data AS (
    SELECT
        day,
        tv_hours,
        evening_tv_minutes
    FROM life.daily_behavioral_summary
),
combined AS (
    SELECT
        lf.day,
        tv.tv_hours,
        tv.evening_tv_minutes,
        lf.sleep_hours,
        lf.deep_sleep_hours,
        lf.sleep_efficiency,
        lf.sleep_performance,
        LEAD(lf.sleep_hours) OVER (ORDER BY lf.day) AS next_night_sleep
    FROM life.daily_facts lf
    LEFT JOIN tv_data tv ON lf.day = tv.day
    WHERE lf.day >= NOW() - INTERVAL '90 days'
)
SELECT
    day,
    tv_hours,
    evening_tv_minutes,
    sleep_hours,
    deep_sleep_hours,
    sleep_efficiency,
    CASE
        WHEN evening_tv_minutes > 120 AND sleep_hours < 7 THEN 'heavy_tv_poor_sleep'
        WHEN evening_tv_minutes > 120 AND sleep_hours >= 7 THEN 'heavy_tv_good_sleep'
        WHEN evening_tv_minutes <= 60 AND sleep_hours < 7 THEN 'light_tv_poor_sleep'
        WHEN evening_tv_minutes <= 60 AND sleep_hours >= 7 THEN 'light_tv_good_sleep'
        ELSE 'no_pattern'
    END AS pattern
FROM combined
ORDER BY day DESC;

-- ============================================================================
-- insights.productivity_recovery_correlation
-- Does high recovery lead to more productive days?
-- ============================================================================

CREATE OR REPLACE VIEW insights.productivity_recovery_correlation AS
SELECT
    p.day,
    p.commits,
    p.pr_events,
    p.productivity_score,
    p.recovery_score,
    p.sleep_hours,
    p.hrv,
    CASE
        WHEN p.recovery_score >= 70 AND p.productivity_score >= 50 THEN 'recovered_productive'
        WHEN p.recovery_score >= 70 AND p.productivity_score < 50 THEN 'recovered_unproductive'
        WHEN p.recovery_score < 70 AND p.productivity_score >= 50 THEN 'tired_productive'
        ELSE 'tired_unproductive'
    END AS pattern
FROM life.daily_productivity p
WHERE p.recovery_score IS NOT NULL
ORDER BY p.day DESC;

-- Grant permissions
GRANT USAGE ON SCHEMA insights TO nexus;
GRANT SELECT ON ALL TABLES IN SCHEMA insights TO nexus;

COMMENT ON SCHEMA insights IS 'Cross-domain correlation analysis views';
COMMENT ON VIEW insights.sleep_recovery_correlation IS 'Sleep quality vs next-day recovery correlation';
COMMENT ON VIEW insights.spending_recovery_correlation IS 'Daily spending vs recovery level correlation';
COMMENT ON VIEW insights.screen_sleep_correlation IS 'Evening TV time vs sleep quality correlation';
COMMENT ON VIEW insights.productivity_recovery_correlation IS 'GitHub productivity vs recovery correlation';
