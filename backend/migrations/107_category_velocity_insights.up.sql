-- Migration 107: Add category_trends to dashboard.get_payload() daily_insights
-- Surfaces top 3 significant category spending trends from finance.mv_category_velocity

CREATE OR REPLACE FUNCTION dashboard.get_payload(for_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    target_date DATE := COALESCE(for_date, life.dubai_today());
    payload JSONB;
    facts_computed TIMESTAMPTZ;
    source_latest TIMESTAMPTZ;
    is_today BOOLEAN;
BEGIN
    is_today := (target_date = life.dubai_today());

    IF NOT EXISTS (SELECT 1 FROM life.daily_facts WHERE day = target_date) THEN
        PERFORM life.refresh_daily_facts(target_date);
    ELSE
        SELECT computed_at INTO facts_computed
        FROM life.daily_facts WHERE day = target_date;

        SELECT GREATEST(
            (SELECT MAX(created_at) FROM health.whoop_recovery
             WHERE CASE WHEN is_today THEN date <= target_date ELSE date = target_date END),
            (SELECT MAX(created_at) FROM health.whoop_sleep
             WHERE CASE WHEN is_today THEN date <= target_date ELSE date = target_date END),
            (SELECT MAX(created_at) FROM health.whoop_strain
             WHERE CASE WHEN is_today THEN date <= target_date ELSE date = target_date END),
            (SELECT MAX(recorded_at) FROM health.metrics
             WHERE metric_type = 'weight'
               AND (recorded_at AT TIME ZONE 'Asia/Dubai')::date = target_date),
            (SELECT MAX(created_at) FROM finance.transactions
             WHERE (transaction_at AT TIME ZONE 'Asia/Dubai')::date = target_date)
        ) INTO source_latest;

        IF source_latest IS NOT NULL AND (facts_computed IS NULL OR source_latest > facts_computed) THEN
            PERFORM life.refresh_daily_facts(target_date);
        END IF;
    END IF;

    SELECT jsonb_build_object(
        'meta', jsonb_build_object(
            'schema_version', 7,
            'generated_at', to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
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
            SELECT jsonb_agg(
                jsonb_build_object(
                    'feed', f.feed,
                    'status', f.status,
                    'last_sync', to_char(f.last_sync AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                    'total_records', f.total_records,
                    'hours_since_sync', f.hours_since_sync
                )
            )
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
            'ranked_insights', insights.get_ranked_insights(target_date),
            'category_trends', (
                SELECT COALESCE(jsonb_agg(
                    jsonb_build_object(
                        'type', 'category_trend',
                        'category', category,
                        'change_pct', ROUND(ABS(velocity_pct), 1),
                        'direction', CASE WHEN velocity_pct > 0 THEN 'up' ELSE 'down' END,
                        'detail', category || ' spending ' ||
                            CASE WHEN velocity_pct > 0 THEN 'up' ELSE 'down' END ||
                            ' ' || ROUND(ABS(velocity_pct), 0) || '% vs prior months'
                    )
                    ORDER BY ABS(velocity_pct) DESC
                ), '[]'::jsonb)
                FROM (
                    SELECT category, velocity_pct
                    FROM finance.mv_category_velocity
                    WHERE trend <> 'insufficient_data'
                      AND ABS(velocity_pct) > 25
                    ORDER BY ABS(velocity_pct) DESC
                    LIMIT 3
                ) top_changes
            )
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
                        'last_sync', to_char(MAX(last_sync) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
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
                        'last_sync', to_char(last_sync AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
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
                'generated_at', to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
            )
        ),
        'domains_status', (
            SELECT COALESCE(jsonb_agg(
                jsonb_build_object(
                    'domain', d.domain,
                    'status', d.status,
                    'as_of', d.as_of,
                    'last_success', d.last_success,
                    'last_error', d.last_error
                )
            ), '[]'::jsonb)
            FROM ops.v_domains_status d
        ),
        'github_activity', COALESCE(life.get_github_activity_widget(14), '{}'::jsonb),
        'calendar_summary', COALESCE(
            (SELECT jsonb_build_object(
                'meeting_count', cs.meeting_count,
                'meeting_hours', cs.meeting_hours,
                'first_meeting', to_char(cs.first_meeting, 'HH24:MI'),
                'last_meeting', to_char(cs.last_meeting, 'HH24:MI')
            )
            FROM life.v_daily_calendar_summary cs
            WHERE cs.day = target_date),
            '{"meeting_count": 0, "meeting_hours": 0, "first_meeting": null, "last_meeting": null}'::jsonb
        )
    ) INTO payload;

    RETURN payload;
END;
$function$;
