-- Migration 081: Sync Runs - Observability layer for all ingest/sync operations
-- Provides: per-domain tracking, advisory lock protection, freshness view

-- sync_runs: one row per sync attempt
CREATE TABLE IF NOT EXISTS ops.sync_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    domain VARCHAR(50) NOT NULL,  -- calendar, receipts, sms_finance, healthkit, whoop, dashboard
    status VARCHAR(20) NOT NULL DEFAULT 'running'
        CHECK (status IN ('running', 'success', 'error', 'skipped')),
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ,
    duration_ms INTEGER GENERATED ALWAYS AS (
        CASE WHEN finished_at IS NOT NULL
            THEN EXTRACT(EPOCH FROM (finished_at - started_at))::integer * 1000
        END
    ) STORED,
    source VARCHAR(50),           -- ios_app, n8n, launchd, cli, manual
    rows_affected INTEGER DEFAULT 0,
    error TEXT,
    meta JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_sync_runs_domain_started ON ops.sync_runs(domain, started_at DESC);
CREATE INDEX idx_sync_runs_status ON ops.sync_runs(status) WHERE status != 'success';

-- Advisory lock helper: hash domain name to int for pg_advisory_lock
CREATE OR REPLACE FUNCTION ops.domain_lock_id(p_domain TEXT) RETURNS BIGINT
LANGUAGE sql IMMUTABLE AS $$
    SELECT abs(hashtext('sync_' || p_domain))::bigint;
$$;

-- Start a sync run with advisory lock (prevents overlapping runs for same domain)
CREATE OR REPLACE FUNCTION ops.start_sync(
    p_domain TEXT,
    p_source TEXT DEFAULT 'unknown'
) RETURNS UUID
LANGUAGE plpgsql AS $$
DECLARE
    v_id UUID;
    v_lock_id BIGINT;
BEGIN
    v_lock_id := ops.domain_lock_id(p_domain);

    -- Try advisory lock (non-blocking). If can't get it, another sync is running.
    IF NOT pg_try_advisory_lock(v_lock_id) THEN
        -- Record a skipped run
        INSERT INTO ops.sync_runs (domain, status, source, finished_at, error)
        VALUES (p_domain, 'skipped', p_source, now(), 'Another sync is already running')
        RETURNING id INTO v_id;
        RETURN v_id;
    END IF;

    INSERT INTO ops.sync_runs (domain, status, source)
    VALUES (p_domain, 'running', p_source)
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- Finish a sync run (releases advisory lock)
CREATE OR REPLACE FUNCTION ops.finish_sync(
    p_run_id UUID,
    p_status TEXT DEFAULT 'success',
    p_rows INTEGER DEFAULT 0,
    p_error TEXT DEFAULT NULL,
    p_meta JSONB DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
    v_domain TEXT;
    v_lock_id BIGINT;
BEGIN
    SELECT domain INTO v_domain FROM ops.sync_runs WHERE id = p_run_id;

    UPDATE ops.sync_runs SET
        status = p_status,
        finished_at = now(),
        rows_affected = p_rows,
        error = p_error,
        meta = COALESCE(p_meta, meta)
    WHERE id = p_run_id;

    -- Release advisory lock
    IF v_domain IS NOT NULL THEN
        v_lock_id := ops.domain_lock_id(v_domain);
        PERFORM pg_advisory_unlock(v_lock_id);
    END IF;
END;
$$;

-- Per-domain freshness view
CREATE OR REPLACE VIEW ops.v_sync_status AS
WITH latest_success AS (
    SELECT DISTINCT ON (domain)
        domain,
        id as last_success_id,
        finished_at as last_success_at,
        rows_affected as last_success_rows,
        duration_ms as last_success_duration_ms,
        source as last_success_source
    FROM ops.sync_runs
    WHERE status = 'success'
    ORDER BY domain, finished_at DESC
),
latest_error AS (
    SELECT DISTINCT ON (domain)
        domain,
        finished_at as last_error_at,
        error as last_error,
        source as last_error_source
    FROM ops.sync_runs
    WHERE status = 'error'
    ORDER BY domain, finished_at DESC
),
running AS (
    SELECT domain, COUNT(*) as running_count
    FROM ops.sync_runs
    WHERE status = 'running'
    GROUP BY domain
),
all_domains AS (
    SELECT DISTINCT domain FROM ops.sync_runs
)
SELECT
    d.domain,
    ls.last_success_at,
    ls.last_success_rows,
    ls.last_success_duration_ms,
    ls.last_success_source,
    le.last_error_at,
    le.last_error,
    COALESCE(r.running_count, 0) as running_count,
    CASE
        WHEN ls.last_success_at IS NULL THEN 'never_synced'
        WHEN ls.last_success_at < now() - INTERVAL '1 hour' THEN 'stale'
        ELSE 'fresh'
    END as freshness,
    EXTRACT(EPOCH FROM (now() - ls.last_success_at))::integer as seconds_since_success
FROM all_domains d
LEFT JOIN latest_success ls USING (domain)
LEFT JOIN latest_error le USING (domain)
LEFT JOIN running r USING (domain);

-- Webhook for iOS to query sync status
-- This will be accessed via n8n webhook
COMMENT ON VIEW ops.v_sync_status IS 'Per-domain sync freshness. Used by iOS app and monitoring.';
COMMENT ON TABLE ops.sync_runs IS 'Audit log of all sync/ingest operations across all domains.';
