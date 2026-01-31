-- Migration: 093_domains_status_and_freshness_fix
-- Purpose: Fix data_freshness timestamp format (raw PG → ISO8601) and add ops.v_domains_status
-- Root cause: iOS ISO8601DateFormatter cannot parse raw Postgres timestamps,
--   causing "No sync" and "Health data delayed" in TodayView
-- Changes:
--   1. Create ops.v_domains_status view (stable contract: domain, status, as_of, last_success, last_error)
--   2. Update get_payload() to format all last_sync timestamps as ISO8601 + include domains_status
-- Created: 2026-01-30

-- ============================================================
-- 1. ops.v_domains_status — stable domain-level health contract
-- ============================================================

CREATE OR REPLACE VIEW ops.v_domains_status AS

SELECT 'health' AS domain,
       CASE WHEN bool_or(status = 'critical') THEN 'critical'
            WHEN bool_or(status = 'stale') THEN 'stale'
            ELSE 'healthy'
       END AS status,
       to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS as_of,
       to_char(MAX(last_sync) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS last_success,
       NULL::text AS last_error
FROM ops.feed_status
WHERE feed IN ('whoop_recovery', 'whoop_sleep', 'whoop_strain', 'weight')

UNION ALL

SELECT 'finance' AS domain,
       COALESCE(
           CASE WHEN bool_or(status = 'critical') THEN 'critical'
                WHEN bool_or(status = 'stale') THEN 'stale'
                ELSE 'healthy'
           END,
           'unknown'
       ) AS status,
       to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS as_of,
       to_char(MAX(last_sync) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS last_success,
       NULL::text AS last_error
FROM ops.feed_status
WHERE feed = 'transactions'

UNION ALL

SELECT 'whoop' AS domain,
       CASE WHEN bool_or(status = 'critical') THEN 'critical'
            WHEN bool_or(status = 'stale') THEN 'stale'
            ELSE 'healthy'
       END AS status,
       to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS as_of,
       to_char(MAX(last_sync) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS last_success,
       NULL::text AS last_error
FROM ops.feed_status
WHERE feed LIKE 'whoop%';

COMMENT ON VIEW ops.v_domains_status IS
'Stable domain-level health contract for iOS. Returns {domain, status, as_of, last_success, last_error} per domain.';

-- ============================================================
-- 2. Update get_payload() — ISO8601 timestamps + domains_status
-- ============================================================

CREATE OR REPLACE FUNCTION dashboard.get_payload(for_date date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    target_date DATE := COALESCE(for_date, life.dubai_today());
    payload JSONB;
    facts_computed TIMESTAMPTZ;
    whoop_latest TIMESTAMPTZ;
BEGIN
    -- Auto-refresh daily_facts if missing for target date
    IF NOT EXISTS (SELECT 1 FROM life.daily_facts WHERE day = target_date) THEN
        PERFORM life.refresh_daily_facts(target_date);
    ELSE
        -- Check if source data is newer than last computation
        SELECT computed_at INTO facts_computed
        FROM life.daily_facts WHERE day = target_date;

        SELECT GREATEST(
            (SELECT MAX(created_at) FROM health.whoop_recovery WHERE date = target_date),
            (SELECT MAX(created_at) FROM health.whoop_sleep WHERE date = target_date),
            (SELECT MAX(created_at) FROM health.whoop_strain WHERE date = target_date)
        ) INTO whoop_latest;

        -- Re-refresh if WHOOP data arrived after last computation
        IF whoop_latest IS NOT NULL AND (facts_computed IS NULL OR whoop_latest > facts_computed) THEN
            PERFORM life.refresh_daily_facts(target_date);
        END IF;
    END IF;

    SELECT jsonb_build_object(
        'meta', jsonb_build_object(
            'schema_version', 5,
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
        )
    ) INTO payload;

    RETURN payload;
END;
$function$;

COMMENT ON FUNCTION dashboard.get_payload(date) IS
'Dashboard payload v5: ISO8601 timestamps, domains_status array, auto-refresh when WHOOP source data is newer';
