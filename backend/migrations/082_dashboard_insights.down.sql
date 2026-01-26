-- Rollback: 082_dashboard_insights
-- Restores dashboard.get_payload() without daily_insights (schema v1)

BEGIN;

CREATE OR REPLACE FUNCTION dashboard.get_payload(for_date DATE DEFAULT NULL)
RETURNS JSONB AS $$
DECLARE
    target_date DATE := COALESCE(for_date, life.dubai_today());
    payload JSONB;
BEGIN
    SELECT jsonb_build_object(
        'meta', jsonb_build_object(
            'schema_version', 1,
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
        )
    ) INTO payload;

    RETURN payload;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION dashboard.get_payload IS 'Complete dashboard payload as JSONB. Deterministic for caching. Call with date for historical views.';

COMMIT;
