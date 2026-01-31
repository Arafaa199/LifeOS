-- Migration: 089_dashboard_auto_refresh
-- Purpose: get_payload() auto-refreshes daily_facts if missing for target date
-- Problem: If daily_facts had no row for today, today_facts was null → iOS decode crash
-- Created: 2026-01-29

CREATE OR REPLACE FUNCTION dashboard.get_payload(for_date date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    target_date DATE := COALESCE(for_date, life.dubai_today());
    payload JSONB;
BEGIN
    -- Auto-refresh daily_facts if missing for target date
    IF NOT EXISTS (SELECT 1 FROM life.daily_facts WHERE day = target_date) THEN
        PERFORM life.refresh_daily_facts(target_date);
    END IF;

    SELECT jsonb_build_object(
        'meta', jsonb_build_object(
            'schema_version', 4,
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
                    'avg_recovery', avg_recovery,
                    'sample_size', sample_size,
                    'days_with_spend', days_with_spend,
                    'confidence', confidence
                )), '[]'::jsonb)
                FROM insights.pattern_detector
                WHERE pattern_flag != 'normal'
                  AND confidence != 'low'
            ),
            'spending_by_recovery', (
                SELECT COALESCE(jsonb_agg(jsonb_build_object(
                    'recovery_level', recovery_level,
                    'days', days,
                    'days_with_spend', days_with_spend,
                    'avg_spend', avg_spend,
                    'confidence', confidence
                )), '[]'::jsonb)
                FROM insights.spending_by_recovery_level
                WHERE confidence != 'low'
            ),
            'today_is', (
                SELECT pattern_flag
                FROM insights.pattern_detector
                WHERE day_name = to_char(target_date, 'FMDay')
                  AND sample_size >= 7
            ),
            'ranked_insights', insights.get_ranked_insights(target_date)
        ),
        'data_freshness', (
            SELECT jsonb_build_object(
                'health', (
                    SELECT jsonb_build_object(
                        'status', CASE
                            WHEN bool_or(status = 'critical') THEN 'critical'
                            WHEN bool_or(status = 'stale') THEN 'stale'
                            ELSE 'healthy'
                        END,
                        'last_sync', MAX(last_sync),
                        'hours_since_sync', ROUND(MIN(hours_since_sync)::numeric, 1),
                        'stale_feeds', COALESCE(
                            jsonb_agg(feed) FILTER (WHERE status IN ('stale', 'critical')),
                            '[]'::jsonb
                        )
                    )
                    FROM ops.feed_status
                    WHERE feed IN ('whoop_recovery', 'whoop_sleep', 'whoop_strain', 'weight')
                ),
                'finance', (
                    SELECT jsonb_build_object(
                        'status', COALESCE(status, 'unknown'),
                        'last_sync', last_sync,
                        'hours_since_sync', ROUND(hours_since_sync::numeric, 1),
                        'stale_feeds', CASE
                            WHEN status IN ('stale', 'critical') THEN jsonb_build_array(feed)
                            ELSE '[]'::jsonb
                        END
                    )
                    FROM ops.feed_status
                    WHERE feed = 'transactions'
                ),
                'overall_status', (
                    SELECT CASE
                        WHEN bool_or(status = 'critical') THEN 'critical'
                        WHEN bool_or(status = 'stale') THEN 'stale'
                        ELSE 'healthy'
                    END
                    FROM ops.feed_status
                ),
                'generated_at', NOW()
            )
        )
    ) INTO payload;

    RETURN payload;
END;
$function$;

COMMENT ON FUNCTION dashboard.get_payload(date) IS
'Dashboard payload with auto-refresh: creates daily_facts if missing for target date';
