-- Migration 032: Add ops.pipeline_health view
-- Task: TASK-M0.2
-- Purpose: Canonical pipeline health view with standardized columns and status values
--
-- This view wraps the existing ops.v_pipeline_health with the exact interface
-- specified in TASK-M0.2:
--   - source, last_event_at, events_24h, stale_after_hours, status
--   - Status: healthy (<stale_after), stale (<2x), dead (>2x or null)

CREATE OR REPLACE VIEW ops.pipeline_health AS
SELECT
    source,
    last_event_at,
    events_24h,
    -- Convert interval to hours for stale_after_hours
    EXTRACT(EPOCH FROM expected_frequency)::int / 3600 AS stale_after_hours,
    -- Map status to healthy/stale/dead
    CASE status
        WHEN 'ok' THEN 'healthy'
        WHEN 'stale' THEN 'stale'
        WHEN 'critical' THEN 'dead'
        WHEN 'never' THEN 'dead'
        ELSE 'dead'
    END AS status,
    -- Include extras for context
    domain,
    hours_since_last,
    notes
FROM ops.v_pipeline_health;

-- Add comment
COMMENT ON VIEW ops.pipeline_health IS 'Canonical pipeline health view per TASK-M0.2. Status: healthy (<stale_after_hours), stale (<2x), dead (>2x or never).';
