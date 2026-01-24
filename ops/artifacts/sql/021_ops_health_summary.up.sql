-- Migration 021: Ops Health Summary View
-- Purpose: System health at a glance for monitoring
-- Created: 2026-01-23

CREATE OR REPLACE VIEW finance.v_ops_health AS
WITH receipt_stats AS (
    SELECT
        COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '24 hours') AS receipts_24h,
        COUNT(*) FILTER (WHERE parse_status = 'needs_review') AS receipts_needing_review,
        COUNT(*) FILTER (WHERE parse_status = 'pending') AS receipts_pending,
        COUNT(*) FILTER (WHERE parse_status = 'failed') AS receipts_failed,
        MAX(created_at) AS last_receipt_at
    FROM finance.receipts
),
raw_event_stats AS (
    SELECT
        COUNT(*) FILTER (WHERE validation_status = 'pending') AS raw_events_pending,
        COUNT(*) FILTER (WHERE validation_status = 'pending' AND created_at < NOW() - INTERVAL '10 minutes') AS raw_events_stale,
        COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '24 hours') AS raw_events_24h,
        MAX(created_at) AS last_raw_event_at
    FROM finance.raw_events
),
source_health AS (
    SELECT json_agg(json_build_object(
        'source', source,
        'last_success_at', last_success_at,
        'count_24h', count_24h
    )) AS sources
    FROM (
        SELECT
            COALESCE(
                CASE
                    WHEN client_id LIKE 'sms-%' THEN 'sms'
                    WHEN client_id LIKE 'rcpt:%' THEN 'receipt'
                    ELSE 'webhook'
                END
            , 'unknown') AS source,
            MAX(created_at) AS last_success_at,
            COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '24 hours') AS count_24h
        FROM finance.transactions
        WHERE is_quarantined = false
        GROUP BY 1
    ) sub
),
template_stats AS (
    SELECT
        COUNT(*) FILTER (WHERE status = 'approved') AS templates_approved,
        COUNT(*) FILTER (WHERE status = 'needs_review') AS templates_pending
    FROM finance.receipt_templates
)
SELECT
    -- Receipt health
    rs.receipts_24h,
    rs.receipts_needing_review,
    rs.receipts_pending,
    rs.receipts_failed,
    rs.last_receipt_at,

    -- Raw event health
    re.raw_events_pending,
    re.raw_events_stale,
    re.raw_events_24h,
    re.last_raw_event_at,

    -- Template health
    ts.templates_approved,
    ts.templates_pending,

    -- Source health
    sh.sources AS source_health,

    -- Invariant checks
    CASE WHEN re.raw_events_stale > 0 THEN 'WARN' ELSE 'OK' END AS stale_events_status,
    CASE WHEN rs.receipts_needing_review > 0 THEN 'WARN' ELSE 'OK' END AS review_status,
    CASE WHEN ts.templates_pending > 0 THEN 'WARN' ELSE 'OK' END AS template_status,

    -- Overall health
    CASE
        WHEN re.raw_events_stale > 0 THEN 'DEGRADED'
        WHEN rs.receipts_failed > 0 THEN 'DEGRADED'
        ELSE 'HEALTHY'
    END AS overall_status,

    CURRENT_TIMESTAMP AS checked_at
FROM receipt_stats rs
CROSS JOIN raw_event_stats re
CROSS JOIN source_health sh
CROSS JOIN template_stats ts;

COMMENT ON VIEW finance.v_ops_health IS 'System health summary for monitoring and alerting';

GRANT SELECT ON finance.v_ops_health TO nexus;
