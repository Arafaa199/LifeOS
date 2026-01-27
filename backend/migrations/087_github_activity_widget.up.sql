-- Migration 087: GitHub Activity Dashboard Widget
-- Creates a function that returns GitHub activity data optimized for dashboard widget consumption.
-- Builds on existing raw.github_events table and life.daily_productivity view.

-- Function: Get GitHub activity widget data as JSON
CREATE OR REPLACE FUNCTION life.get_github_activity_widget(p_days INTEGER DEFAULT 30)
RETURNS JSONB
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    result JSONB;
    v_streak INTEGER;
    v_max_streak INTEGER;
BEGIN
    -- Calculate streaks using ascending order (classic day - row_number grouping)
    WITH ordered_days AS (
        SELECT DISTINCT (created_at_github AT TIME ZONE 'Asia/Dubai')::date AS day
        FROM raw.github_events
        WHERE event_type = 'PushEvent'
          AND created_at_github >= NOW() - INTERVAL '90 days'
    ),
    streak_calc AS (
        SELECT day,
               day - (ROW_NUMBER() OVER (ORDER BY day))::int AS grp
        FROM ordered_days
    ),
    streaks AS (
        SELECT grp, MIN(day) AS streak_start, MAX(day) AS streak_end, COUNT(*)::int AS streak_len
        FROM streak_calc
        GROUP BY grp
    )
    SELECT
        COALESCE((SELECT streak_len FROM streaks WHERE streak_end >= CURRENT_DATE - 1 ORDER BY streak_end DESC LIMIT 1), 0),
        COALESCE((SELECT MAX(streak_len) FROM streaks), 0)
    INTO v_streak, v_max_streak;

    -- Build the full widget JSON
    SELECT jsonb_build_object(
        'summary', (
            SELECT jsonb_build_object(
                'active_days_7d', COUNT(DISTINCT day) FILTER (WHERE day >= CURRENT_DATE - 6),
                'active_days_30d', COUNT(DISTINCT day) FILTER (WHERE day >= CURRENT_DATE - 29),
                'push_events_7d', SUM(push_events) FILTER (WHERE day >= CURRENT_DATE - 6),
                'push_events_30d', SUM(push_events) FILTER (WHERE day >= CURRENT_DATE - 29),
                'repos_7d', (
                    SELECT COUNT(DISTINCT repo_name) FROM raw.github_events
                    WHERE (created_at_github AT TIME ZONE 'Asia/Dubai')::date >= CURRENT_DATE - 6
                ),
                'current_streak', v_streak,
                'max_streak_90d', v_max_streak,
                'as_of_date', CURRENT_DATE
            )
            FROM life.daily_productivity
            WHERE day >= CURRENT_DATE - 29
        ),
        'daily', (
            SELECT COALESCE(jsonb_agg(
                jsonb_build_object(
                    'day', d.day,
                    'push_events', COALESCE(p.push_events, 0),
                    'repos_touched', COALESCE(p.repos_touched, 0),
                    'productivity_score', COALESCE(p.productivity_score, 0)
                ) ORDER BY d.day DESC
            ), '[]'::jsonb)
            FROM generate_series(CURRENT_DATE - (p_days - 1), CURRENT_DATE, '1 day') AS d(day)
            LEFT JOIN life.daily_productivity p ON p.day = d.day
        ),
        'repos', (
            SELECT COALESCE(jsonb_agg(
                jsonb_build_object(
                    'name', repo_name,
                    'events_30d', cnt,
                    'last_active', last_active
                ) ORDER BY last_active DESC
            ), '[]'::jsonb)
            FROM (
                SELECT repo_name, COUNT(*) AS cnt, MAX((created_at_github AT TIME ZONE 'Asia/Dubai')::date) AS last_active
                FROM raw.github_events
                WHERE created_at_github >= NOW() - INTERVAL '30 days'
                GROUP BY repo_name
            ) r
        ),
        'generated_at', NOW()
    ) INTO result;

    RETURN result;
END;
$$;

-- Convenience view for quick querying
CREATE OR REPLACE VIEW life.v_github_activity_widget AS
SELECT life.get_github_activity_widget(14) AS widget_data;

COMMENT ON FUNCTION life.get_github_activity_widget IS 'Returns GitHub activity data as JSON for dashboard widget. Default 30 days of daily breakdown.';
