-- Migration: 028_cross_domain_anomalies
-- Adds cross-domain anomaly detection views
-- TASK-065: Anomaly Detection Across Domains

-- ============================================================================
-- insights.daily_anomalies - Detect unusual patterns across domains
-- ============================================================================

CREATE OR REPLACE VIEW insights.daily_anomalies AS
WITH baselines AS (
    SELECT
        AVG(spend_total) AS avg_spend,
        STDDEV(spend_total) AS std_spend,
        AVG(recovery_score) AS avg_recovery,
        STDDEV(recovery_score) AS std_recovery,
        AVG(sleep_hours) AS avg_sleep,
        STDDEV(sleep_hours) AS std_sleep,
        AVG(hrv) AS avg_hrv,
        STDDEV(hrv) AS std_hrv
    FROM life.daily_facts
    WHERE day >= NOW() - INTERVAL '30 days'
      AND day < NOW() - INTERVAL '1 day'  -- Exclude today
),
daily_z_scores AS (
    SELECT
        lf.day,
        lf.spend_total,
        lf.recovery_score,
        lf.sleep_hours,
        lf.hrv,
        -- Z-scores for anomaly detection
        CASE WHEN b.std_spend > 0
            THEN (lf.spend_total - b.avg_spend) / b.std_spend
            ELSE 0 END AS spend_z_score,
        CASE WHEN b.std_recovery > 0
            THEN (lf.recovery_score - b.avg_recovery) / b.std_recovery
            ELSE 0 END AS recovery_z_score,
        CASE WHEN b.std_sleep > 0
            THEN (lf.sleep_hours - b.avg_sleep) / b.std_sleep
            ELSE 0 END AS sleep_z_score,
        CASE WHEN b.std_hrv > 0
            THEN (lf.hrv - b.avg_hrv) / b.std_hrv
            ELSE 0 END AS hrv_z_score
    FROM life.daily_facts lf
    CROSS JOIN baselines b
    WHERE lf.day >= NOW() - INTERVAL '7 days'
)
SELECT
    day,
    spend_total,
    recovery_score,
    sleep_hours,
    hrv,
    ROUND(spend_z_score::numeric, 2) AS spend_z_score,
    ROUND(recovery_z_score::numeric, 2) AS recovery_z_score,
    ROUND(sleep_z_score::numeric, 2) AS sleep_z_score,
    ROUND(hrv_z_score::numeric, 2) AS hrv_z_score,
    -- Flag anomalies (z-score > 2 or < -2)
    ARRAY_REMOVE(ARRAY[
        CASE WHEN ABS(spend_z_score) > 2 THEN
            CASE WHEN spend_z_score > 0 THEN 'high_spend' ELSE 'low_spend' END
        END,
        CASE WHEN ABS(recovery_z_score) > 2 THEN
            CASE WHEN recovery_z_score > 0 THEN 'high_recovery' ELSE 'low_recovery' END
        END,
        CASE WHEN ABS(sleep_z_score) > 2 THEN
            CASE WHEN sleep_z_score > 0 THEN 'high_sleep' ELSE 'low_sleep' END
        END,
        CASE WHEN ABS(hrv_z_score) > 2 THEN
            CASE WHEN hrv_z_score > 0 THEN 'high_hrv' ELSE 'low_hrv' END
        END
    ], NULL) AS anomalies
FROM daily_z_scores
ORDER BY day DESC;

-- ============================================================================
-- insights.cross_domain_alerts - Specific multi-domain anomaly patterns
-- ============================================================================

CREATE OR REPLACE VIEW insights.cross_domain_alerts AS
SELECT
    day,
    'high_spend_low_recovery' AS alert_type,
    'Spent ' || ROUND(spend_total::numeric, 0) || ' on a low-recovery day (' || ROUND(recovery_score::numeric, 0) || '%)' AS description,
    'warning' AS severity
FROM life.daily_facts
WHERE spend_total > (SELECT AVG(spend_total) * 2 FROM life.daily_facts WHERE spend_total > 0)
  AND recovery_score < 40
  AND day >= NOW() - INTERVAL '7 days'

UNION ALL

SELECT
    day,
    'poor_sleep_high_strain' AS alert_type,
    'Only ' || ROUND(sleep_hours::numeric, 1) || 'h sleep before high strain day (' || ROUND(strain::numeric, 1) || ')' AS description,
    'info' AS severity
FROM life.daily_facts
WHERE sleep_hours < 6
  AND strain > (SELECT AVG(strain) * 1.3 FROM life.daily_facts WHERE strain > 0)
  AND day >= NOW() - INTERVAL '7 days'

UNION ALL

SELECT
    day,
    'hrv_drop_pattern' AS alert_type,
    'HRV dropped to ' || ROUND(hrv::numeric, 0) || ' (3-day low)' AS description,
    'warning' AS severity
FROM life.daily_facts lf
WHERE hrv IS NOT NULL
  AND hrv < (SELECT MIN(hrv) FROM life.daily_facts WHERE day BETWEEN lf.day - INTERVAL '3 days' AND lf.day - INTERVAL '1 day')
  AND day >= NOW() - INTERVAL '7 days'

UNION ALL

SELECT
    day,
    'consecutive_deficit_days' AS alert_type,
    'Calorie deficit for 5+ consecutive days' AS description,
    'info' AS severity
FROM (
    SELECT
        day,
        SUM(CASE WHEN calories_active > COALESCE(calories_consumed, 0) THEN 1 ELSE 0 END)
            OVER (ORDER BY day ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS deficit_streak
    FROM life.daily_facts
    WHERE day >= NOW() - INTERVAL '14 days'
) streak
WHERE deficit_streak >= 5

ORDER BY day DESC, severity;

-- ============================================================================
-- insights.pattern_detector - Detect recurring patterns
-- ============================================================================

CREATE OR REPLACE VIEW insights.pattern_detector AS
WITH day_patterns AS (
    SELECT
        EXTRACT(DOW FROM day) AS day_of_week,
        AVG(spend_total) AS avg_spend,
        AVG(recovery_score) AS avg_recovery,
        AVG(sleep_hours) AS avg_sleep,
        COUNT(*) AS sample_size
    FROM life.daily_facts
    WHERE day >= NOW() - INTERVAL '60 days'
    GROUP BY EXTRACT(DOW FROM day)
)
SELECT
    CASE day_of_week
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END AS day_name,
    ROUND(avg_spend::numeric, 2) AS avg_spend,
    ROUND(avg_recovery::numeric, 1) AS avg_recovery,
    ROUND(avg_sleep::numeric, 2) AS avg_sleep,
    sample_size,
    -- Flag unusual day patterns
    CASE
        WHEN avg_spend > (SELECT AVG(avg_spend) * 1.5 FROM day_patterns) THEN 'high_spend_day'
        WHEN avg_recovery < (SELECT AVG(avg_recovery) * 0.7 FROM day_patterns) THEN 'low_recovery_day'
        WHEN avg_sleep < (SELECT AVG(avg_sleep) * 0.8 FROM day_patterns) THEN 'poor_sleep_day'
        ELSE 'normal'
    END AS pattern_flag
FROM day_patterns
ORDER BY day_of_week;

-- Grant permissions
GRANT SELECT ON insights.daily_anomalies TO nexus;
GRANT SELECT ON insights.cross_domain_alerts TO nexus;
GRANT SELECT ON insights.pattern_detector TO nexus;

COMMENT ON VIEW insights.daily_anomalies IS 'Daily anomaly detection using z-scores across all domains';
COMMENT ON VIEW insights.cross_domain_alerts IS 'Specific multi-domain anomaly patterns with descriptions';
COMMENT ON VIEW insights.pattern_detector IS 'Day-of-week patterns for behavior analysis';
