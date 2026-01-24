-- Migration: 044_screen_sleep_aggregation
-- TASK-C2: Screen Time vs Sleep Quality Correlation
-- Enhanced views with aggregation, statistics, and correlation coefficient

-- ============================================================================
-- insights.tv_sleep_daily
-- Daily TV watching linked to same-night and next-night sleep quality
-- ============================================================================

CREATE OR REPLACE VIEW insights.tv_sleep_daily AS
WITH tv_with_sleep AS (
    SELECT
        lf.day,
        COALESCE(dbs.tv_hours, 0) AS tv_hours,
        COALESCE(dbs.evening_tv_minutes, 0) AS evening_tv_minutes,
        lf.sleep_minutes,
        -- Compute sleep_hours from sleep_minutes if not populated
        COALESCE(lf.sleep_hours, ROUND(lf.sleep_minutes::numeric / 60, 2)) AS sleep_hours,
        lf.sleep_performance,
        lf.deep_sleep_minutes,
        CASE
            WHEN lf.sleep_minutes > 0
            THEN ROUND((lf.deep_sleep_minutes::numeric / lf.sleep_minutes) * 100, 1)
            ELSE NULL
        END AS deep_sleep_pct,
        -- Bucket TV hours before bed (evening_tv_minutes / 60)
        CASE
            WHEN COALESCE(dbs.evening_tv_minutes, 0) = 0 THEN 'none'
            WHEN dbs.evening_tv_minutes <= 60 THEN 'light'
            WHEN dbs.evening_tv_minutes <= 120 THEN 'moderate'
            ELSE 'heavy'
        END AS tv_bucket,
        -- Get next day's sleep for TV impact analysis (compute from minutes)
        LEAD(COALESCE(lf.sleep_hours, ROUND(lf.sleep_minutes::numeric / 60, 2))) OVER (ORDER BY lf.day) AS next_night_sleep_hours,
        LEAD(lf.sleep_performance) OVER (ORDER BY lf.day) AS next_night_sleep_performance,
        LEAD(lf.deep_sleep_minutes) OVER (ORDER BY lf.day) AS next_night_deep_sleep_min
    FROM life.daily_facts lf
    LEFT JOIN life.daily_behavioral_summary dbs ON lf.day = dbs.day
    WHERE lf.day >= CURRENT_DATE - INTERVAL '90 days'
)
SELECT
    day,
    tv_hours,
    evening_tv_minutes,
    tv_bucket,
    sleep_hours,
    sleep_performance,
    deep_sleep_minutes,
    deep_sleep_pct,
    next_night_sleep_hours,
    next_night_sleep_performance,
    next_night_deep_sleep_min
FROM tv_with_sleep
ORDER BY day DESC;

-- ============================================================================
-- insights.tv_sleep_aggregation
-- Aggregated statistics by TV bucket - answers "Does TV before bed hurt sleep?"
-- ============================================================================

CREATE OR REPLACE VIEW insights.tv_sleep_aggregation AS
WITH daily_data AS (
    SELECT
        tv_bucket,
        evening_tv_minutes,
        next_night_sleep_hours,
        next_night_sleep_performance,
        -- Calculate deep sleep % for next night
        CASE
            WHEN next_night_deep_sleep_min > 0 AND next_night_sleep_hours > 0
            THEN ROUND((next_night_deep_sleep_min::numeric / (next_night_sleep_hours * 60)) * 100, 1)
            ELSE NULL
        END AS next_night_deep_sleep_pct
    FROM insights.tv_sleep_daily
    WHERE next_night_sleep_hours IS NOT NULL
),
global_stats AS (
    SELECT
        AVG(next_night_sleep_hours) AS global_avg_sleep_hours,
        STDDEV(next_night_sleep_hours) AS global_stddev_sleep_hours,
        AVG(next_night_sleep_performance) AS global_avg_sleep_performance,
        COUNT(*) AS total_samples
    FROM daily_data
    WHERE next_night_sleep_hours IS NOT NULL
)
SELECT
    d.tv_bucket,
    COUNT(*) AS sample_count,
    ROUND(AVG(d.evening_tv_minutes)::numeric, 0) AS avg_tv_minutes,
    ROUND(AVG(d.next_night_sleep_hours)::numeric, 2) AS avg_sleep_hours,
    ROUND(AVG(d.next_night_sleep_performance)::numeric, 0) AS avg_sleep_score,
    ROUND(AVG(d.next_night_deep_sleep_pct)::numeric, 1) AS avg_deep_sleep_pct,
    -- Z-score: how different is this bucket from global average?
    CASE
        WHEN g.global_stddev_sleep_hours > 0
        THEN ROUND(
            (AVG(d.next_night_sleep_hours) - g.global_avg_sleep_hours) / g.global_stddev_sleep_hours,
            2
        )
        ELSE 0
    END AS z_score,
    -- Statistical significance indicator
    CASE
        WHEN COUNT(*) < 5 THEN 'insufficient_data'
        WHEN COUNT(*) < 10 THEN 'low_confidence'
        WHEN ABS(
            CASE
                WHEN g.global_stddev_sleep_hours > 0
                THEN (AVG(d.next_night_sleep_hours) - g.global_avg_sleep_hours) / g.global_stddev_sleep_hours
                ELSE 0
            END
        ) < 0.5 THEN 'within_normal'
        WHEN ABS(
            CASE
                WHEN g.global_stddev_sleep_hours > 0
                THEN (AVG(d.next_night_sleep_hours) - g.global_avg_sleep_hours) / g.global_stddev_sleep_hours
                ELSE 0
            END
        ) < 1.0 THEN 'notable'
        ELSE 'significant'
    END AS significance
FROM daily_data d
CROSS JOIN global_stats g
WHERE d.next_night_sleep_hours IS NOT NULL
GROUP BY d.tv_bucket, g.global_avg_sleep_hours, g.global_stddev_sleep_hours, g.total_samples
ORDER BY
    CASE d.tv_bucket
        WHEN 'none' THEN 1
        WHEN 'light' THEN 2
        WHEN 'moderate' THEN 3
        WHEN 'heavy' THEN 4
    END;

-- ============================================================================
-- insights.tv_sleep_correlation_stats
-- Pearson correlation coefficient between evening TV minutes and sleep quality
-- ============================================================================

CREATE OR REPLACE VIEW insights.tv_sleep_correlation_stats AS
WITH valid_pairs AS (
    SELECT
        COALESCE(evening_tv_minutes, 0)::numeric AS x, -- TV minutes
        next_night_sleep_hours::numeric AS y           -- Sleep hours
    FROM insights.tv_sleep_daily
    WHERE next_night_sleep_hours IS NOT NULL
),
stats AS (
    SELECT
        COUNT(*) AS n,
        AVG(x) AS avg_x,
        AVG(y) AS avg_y,
        STDDEV_POP(x) AS stddev_x,
        STDDEV_POP(y) AS stddev_y,
        SUM((x - (SELECT AVG(x) FROM valid_pairs)) * (y - (SELECT AVG(y) FROM valid_pairs))) AS covariance_numerator
    FROM valid_pairs
)
SELECT
    n AS sample_count,
    ROUND(avg_x, 1) AS avg_tv_minutes,
    ROUND(avg_y, 2) AS avg_sleep_hours,
    -- Pearson correlation coefficient: r = Σ((x-x̄)(y-ȳ)) / ((n-1) * σx * σy)
    CASE
        WHEN n < 3 THEN NULL
        WHEN stddev_x = 0 OR stddev_y = 0 THEN 0
        ELSE ROUND(
            covariance_numerator / ((n - 1) * stddev_x * stddev_y),
            3
        )
    END AS correlation_coefficient,
    -- Interpret the correlation
    CASE
        WHEN n < 3 THEN 'insufficient_data'
        WHEN stddev_x = 0 OR stddev_y = 0 OR stddev_x IS NULL OR stddev_y IS NULL THEN 'no_variation'
        WHEN ABS(covariance_numerator / NULLIF((n - 1) * stddev_x * stddev_y, 0)) < 0.1 THEN 'negligible'
        WHEN ABS(covariance_numerator / NULLIF((n - 1) * stddev_x * stddev_y, 0)) < 0.3 THEN 'weak'
        WHEN ABS(covariance_numerator / NULLIF((n - 1) * stddev_x * stddev_y, 0)) < 0.5 THEN 'moderate'
        WHEN ABS(covariance_numerator / NULLIF((n - 1) * stddev_x * stddev_y, 0)) < 0.7 THEN 'strong'
        ELSE 'very_strong'
    END AS correlation_strength,
    -- Direction
    CASE
        WHEN n < 3 OR stddev_x = 0 OR stddev_y = 0 OR stddev_x IS NULL OR stddev_y IS NULL THEN NULL
        WHEN covariance_numerator / NULLIF((n - 1) * stddev_x * stddev_y, 0) > 0.05 THEN 'positive'
        WHEN covariance_numerator / NULLIF((n - 1) * stddev_x * stddev_y, 0) < -0.05 THEN 'negative'
        ELSE 'none'
    END AS correlation_direction,
    -- Finding text
    CASE
        WHEN n < 10 THEN 'Insufficient data (need 10+ days with both TV and sleep data)'
        WHEN stddev_x = 0 OR stddev_y = 0 OR stddev_x IS NULL OR stddev_y IS NULL THEN 'No variation in TV time or sleep - cannot calculate correlation'
        WHEN ABS(covariance_numerator / NULLIF((n - 1) * stddev_x * stddev_y, 0)) < 0.1 THEN 'No meaningful correlation between TV time and sleep quality'
        WHEN covariance_numerator / NULLIF((n - 1) * stddev_x * stddev_y, 0) < -0.3 THEN 'More TV time correlates with WORSE sleep quality'
        WHEN covariance_numerator / NULLIF((n - 1) * stddev_x * stddev_y, 0) > 0.3 THEN 'More TV time correlates with BETTER sleep quality (unexpected)'
        ELSE 'Weak or no clear pattern between TV time and sleep quality'
    END AS finding
FROM stats;

-- ============================================================================
-- insights.tv_sleep_summary
-- Dashboard-ready summary combining all insights
-- ============================================================================

CREATE OR REPLACE VIEW insights.tv_sleep_summary AS
SELECT
    (SELECT sample_count FROM insights.tv_sleep_correlation_stats) AS days_analyzed,
    (SELECT correlation_coefficient FROM insights.tv_sleep_correlation_stats) AS correlation_coefficient,
    (SELECT correlation_strength FROM insights.tv_sleep_correlation_stats) AS correlation_strength,
    (SELECT correlation_direction FROM insights.tv_sleep_correlation_stats) AS correlation_direction,
    (SELECT finding FROM insights.tv_sleep_correlation_stats) AS finding,
    (SELECT avg_sleep_hours FROM insights.tv_sleep_aggregation WHERE tv_bucket = 'none') AS no_tv_avg_sleep,
    (SELECT avg_sleep_hours FROM insights.tv_sleep_aggregation WHERE tv_bucket = 'heavy') AS heavy_tv_avg_sleep,
    -- Calculate percentage difference
    CASE
        WHEN (SELECT avg_sleep_hours FROM insights.tv_sleep_aggregation WHERE tv_bucket = 'none') IS NOT NULL
         AND (SELECT avg_sleep_hours FROM insights.tv_sleep_aggregation WHERE tv_bucket = 'heavy') IS NOT NULL
         AND (SELECT avg_sleep_hours FROM insights.tv_sleep_aggregation WHERE tv_bucket = 'none') > 0
        THEN ROUND(
            (((SELECT avg_sleep_hours FROM insights.tv_sleep_aggregation WHERE tv_bucket = 'heavy') -
              (SELECT avg_sleep_hours FROM insights.tv_sleep_aggregation WHERE tv_bucket = 'none')) /
             (SELECT avg_sleep_hours FROM insights.tv_sleep_aggregation WHERE tv_bucket = 'none')) * 100,
            1
        )
        ELSE NULL
    END AS heavy_vs_none_pct_diff;

-- Grant permissions
GRANT SELECT ON insights.tv_sleep_daily TO nexus;
GRANT SELECT ON insights.tv_sleep_aggregation TO nexus;
GRANT SELECT ON insights.tv_sleep_correlation_stats TO nexus;
GRANT SELECT ON insights.tv_sleep_summary TO nexus;

COMMENT ON VIEW insights.tv_sleep_daily IS 'Daily TV viewing linked to next-night sleep quality';
COMMENT ON VIEW insights.tv_sleep_aggregation IS 'Aggregated TV vs sleep statistics by TV bucket (none/light/moderate/heavy)';
COMMENT ON VIEW insights.tv_sleep_correlation_stats IS 'Pearson correlation coefficient between evening TV and sleep quality';
COMMENT ON VIEW insights.tv_sleep_summary IS 'Dashboard-ready summary of TV vs sleep correlation findings';
