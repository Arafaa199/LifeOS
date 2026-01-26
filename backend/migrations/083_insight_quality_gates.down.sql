-- Rollback: 083_insight_quality_gates
-- Restores views to pre-quality-gate versions (027/028 originals)
-- Restores dashboard.get_payload() to 082 version (schema v2)

BEGIN;

-- Drop ranked insights function
DROP FUNCTION IF EXISTS insights.get_ranked_insights(DATE);

-- Restore spending_by_recovery_level (original from 027)
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

-- Restore pattern_detector (original from 028)
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
    CASE
        WHEN avg_spend > (SELECT AVG(avg_spend) * 1.5 FROM day_patterns) THEN 'high_spend_day'
        WHEN avg_recovery < (SELECT AVG(avg_recovery) * 0.7 FROM day_patterns) THEN 'low_recovery_day'
        WHEN avg_sleep < (SELECT AVG(avg_sleep) * 0.8 FROM day_patterns) THEN 'poor_sleep_day'
        ELSE 'normal'
    END AS pattern_flag
FROM day_patterns
ORDER BY day_of_week;

-- Restore dashboard.get_payload to 082 version (schema v2, no quality gates)
CREATE OR REPLACE FUNCTION dashboard.get_payload(for_date DATE DEFAULT NULL)
RETURNS JSONB AS $$
DECLARE
    target_date DATE := COALESCE(for_date, life.dubai_today());
    payload JSONB;
BEGIN
    SELECT jsonb_build_object(
        'meta', jsonb_build_object(
            'schema_version', 2,
            'generated_at', NOW(),
            'for_date', target_date,
            'timezone', 'Asia/Dubai'
        ),
        'today_facts', (
            SELECT to_jsonb(t.*) - 'schema_version' - 'generated_at' - 'for_date'
            FROM dashboard.v_today t
        ),
        'trends', (
            SELECT jsonb_agg(to_jsonb(t.*) - 'schema_version' - 'generated_at')
            FROM dashboard.v_trends t
        ),
        'feed_status', (
            SELECT jsonb_agg(to_jsonb(f.*))
            FROM ops.feed_status f
        ),
        'recent_events', (
            SELECT COALESCE(jsonb_agg(to_jsonb(e.*)), '[]'::jsonb)
            FROM dashboard.v_recent_events e
        ),
        'stale_feeds', (
            SELECT COALESCE(jsonb_agg(feed), '[]'::jsonb)
            FROM ops.feed_status
            WHERE status IN ('stale', 'critical')
        ),
        'daily_insights', jsonb_build_object(
            'alerts', (
                SELECT COALESCE(jsonb_agg(jsonb_build_object(
                    'alert_type', alert_type,
                    'severity', severity,
                    'description', description
                )), '[]'::jsonb)
                FROM insights.cross_domain_alerts
                WHERE day = target_date
            ),
            'patterns', (
                SELECT COALESCE(jsonb_agg(jsonb_build_object(
                    'day_name', day_name,
                    'pattern_flag', pattern_flag,
                    'avg_spend', avg_spend,
                    'avg_recovery', avg_recovery
                )), '[]'::jsonb)
                FROM insights.pattern_detector
                WHERE pattern_flag != 'normal'
            ),
            'spending_by_recovery', (
                SELECT COALESCE(jsonb_agg(jsonb_build_object(
                    'recovery_level', recovery_level,
                    'days', days,
                    'avg_spend', avg_spend
                )), '[]'::jsonb)
                FROM insights.spending_by_recovery_level
            ),
            'today_is', (
                SELECT pattern_flag
                FROM insights.pattern_detector
                WHERE day_name = to_char(target_date, 'FMDay')
            )
        )
    ) INTO payload;

    RETURN payload;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION dashboard.get_payload IS 'Complete dashboard payload as JSONB with daily insights. Schema v2. Deterministic for caching. Call with date for historical views.';

COMMIT;
