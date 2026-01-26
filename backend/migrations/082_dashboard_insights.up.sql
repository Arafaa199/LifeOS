-- Migration: 082_dashboard_insights
-- Extends dashboard.get_payload() to include daily insights
-- Sources: insights.cross_domain_alerts, insights.pattern_detector, insights.spending_by_recovery_level

BEGIN;

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
