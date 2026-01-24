-- Migration: 026_github_activity
-- Adds GitHub activity tracking tables and views
-- TASK-062: GitHub Activity Sync

-- ============================================================================
-- raw.github_events - Store raw GitHub events
-- ============================================================================

CREATE TABLE IF NOT EXISTS raw.github_events (
    id BIGSERIAL PRIMARY KEY,
    github_event_id TEXT UNIQUE,
    event_type TEXT NOT NULL,
    repo_name TEXT NOT NULL,
    created_at_github TIMESTAMPTZ NOT NULL,
    payload JSONB DEFAULT '{}'::jsonb,
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_github_events_created_at ON raw.github_events(created_at_github DESC);
CREATE INDEX idx_github_events_event_type ON raw.github_events(event_type);
CREATE INDEX idx_github_events_repo ON raw.github_events(repo_name);

-- ============================================================================
-- life.daily_productivity - Aggregate daily productivity metrics
-- ============================================================================

CREATE OR REPLACE VIEW life.daily_productivity AS
WITH daily_github AS (
    SELECT
        (created_at_github AT TIME ZONE 'Asia/Dubai')::date AS day,
        COUNT(*) FILTER (WHERE event_type = 'PushEvent') AS push_events,
        COUNT(*) FILTER (WHERE event_type = 'PullRequestEvent') AS pr_events,
        COUNT(*) FILTER (WHERE event_type = 'IssuesEvent') AS issue_events,
        COUNT(*) FILTER (WHERE event_type = 'CreateEvent') AS create_events,
        COUNT(DISTINCT repo_name) AS repos_touched,
        -- Calculate commits from PushEvent payload
        COALESCE(SUM(
            CASE WHEN event_type = 'PushEvent'
            THEN (payload->>'size')::int ELSE 0 END
        ), 0) AS commits,
        -- Estimate lines changed (if available in payload)
        COALESCE(SUM(
            CASE WHEN event_type = 'PushEvent'
            THEN (payload->>'distinct_size')::int ELSE 0 END
        ), 0) AS distinct_commits
    FROM raw.github_events
    WHERE created_at_github >= NOW() - INTERVAL '90 days'
    GROUP BY 1
)
SELECT
    g.day,
    g.commits,
    g.push_events,
    g.pr_events,
    g.issue_events,
    g.repos_touched,
    -- Productivity score (0-100)
    LEAST(100, (
        g.commits * 10 +
        g.pr_events * 20 +
        g.issue_events * 5 +
        g.push_events * 2
    )) AS productivity_score,
    -- Compare with recovery if available
    lf.recovery_score,
    lf.sleep_hours,
    lf.hrv
FROM daily_github g
LEFT JOIN life.daily_facts lf ON g.day = lf.day
ORDER BY g.day DESC;

-- ============================================================================
-- Function to ingest GitHub event
-- ============================================================================

CREATE OR REPLACE FUNCTION raw.ingest_github_event(
    p_github_event_id TEXT,
    p_event_type TEXT,
    p_repo_name TEXT,
    p_created_at TIMESTAMPTZ,
    p_payload JSONB DEFAULT '{}'::jsonb
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id BIGINT;
BEGIN
    INSERT INTO raw.github_events (
        github_event_id,
        event_type,
        repo_name,
        created_at_github,
        payload
    ) VALUES (
        p_github_event_id,
        p_event_type,
        p_repo_name,
        p_created_at,
        p_payload
    )
    ON CONFLICT (github_event_id) DO NOTHING
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$function$;

-- Grant permissions
GRANT SELECT, INSERT ON raw.github_events TO nexus;
GRANT USAGE, SELECT ON SEQUENCE raw.github_events_id_seq TO nexus;
GRANT SELECT ON life.daily_productivity TO nexus;
GRANT EXECUTE ON FUNCTION raw.ingest_github_event(TEXT, TEXT, TEXT, TIMESTAMPTZ, JSONB) TO nexus;

COMMENT ON TABLE raw.github_events IS 'Raw GitHub events synced daily via n8n';
COMMENT ON VIEW life.daily_productivity IS 'Daily productivity metrics from GitHub activity with health correlation';
COMMENT ON FUNCTION raw.ingest_github_event IS 'Ingest a GitHub event with deduplication by event ID';
