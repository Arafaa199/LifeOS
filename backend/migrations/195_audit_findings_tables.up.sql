-- Migration 195: Audit findings persistence
-- Tables for storing homelab audit run history and individual check results

CREATE TABLE IF NOT EXISTS ops.audit_runs (
    id SERIAL PRIMARY KEY,
    run_id UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    tier TEXT NOT NULL CHECK (tier IN ('quick', 'standard', 'full', 'domain', 'device')),
    scope TEXT NOT NULL DEFAULT 'all',
    trigger TEXT NOT NULL CHECK (trigger IN ('automated', 'on-demand')),
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    overall_verdict TEXT CHECK (overall_verdict IN ('HEALTHY', 'DEGRADED', 'CRITICAL')),
    pass_count INT NOT NULL DEFAULT 0,
    warn_count INT NOT NULL DEFAULT 0,
    fail_count INT NOT NULL DEFAULT 0,
    skip_count INT NOT NULL DEFAULT 0,
    info_count INT NOT NULL DEFAULT 0,
    flatfile_path TEXT,
    summary TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ops.audit_findings (
    id SERIAL PRIMARY KEY,
    run_id UUID NOT NULL REFERENCES ops.audit_runs(run_id) ON DELETE CASCADE,
    section CHAR(1) NOT NULL CHECK (section IN ('A','B','C','D','E','F','G','H','I','J')),
    check_id TEXT NOT NULL,
    check_name TEXT NOT NULL,
    device TEXT,
    verdict TEXT NOT NULL CHECK (verdict IN ('PASS', 'WARN', 'FAIL', 'INFO', 'SKIP')),
    metric_value TEXT,
    threshold TEXT,
    detail TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_runs_started_at ON ops.audit_runs(started_at DESC);
CREATE INDEX idx_audit_findings_run_id ON ops.audit_findings(run_id);
CREATE INDEX idx_audit_findings_verdict ON ops.audit_findings(verdict) WHERE verdict IN ('WARN', 'FAIL');

-- Helper view: latest run summary
CREATE OR REPLACE VIEW ops.v_latest_audit AS
SELECT
    r.run_id,
    r.tier,
    r.scope,
    r.trigger,
    r.started_at,
    r.completed_at,
    r.overall_verdict,
    r.pass_count,
    r.warn_count,
    r.fail_count,
    r.skip_count,
    r.info_count,
    r.flatfile_path,
    r.summary
FROM ops.audit_runs r
ORDER BY r.started_at DESC
LIMIT 1;

-- Helper view: open issues (WARN + FAIL from latest run)
CREATE OR REPLACE VIEW ops.v_audit_open_issues AS
SELECT
    f.check_id,
    f.check_name,
    f.device,
    f.verdict,
    f.metric_value,
    f.threshold,
    f.detail,
    r.started_at AS audit_date,
    r.tier
FROM ops.audit_findings f
JOIN ops.audit_runs r ON r.run_id = f.run_id
WHERE r.run_id = (SELECT run_id FROM ops.audit_runs ORDER BY started_at DESC LIMIT 1)
  AND f.verdict IN ('WARN', 'FAIL')
ORDER BY
    CASE f.verdict WHEN 'FAIL' THEN 0 WHEN 'WARN' THEN 1 END,
    f.section, f.check_id;

-- Helper: audit history trend (last 30 runs)
CREATE OR REPLACE VIEW ops.v_audit_trend AS
SELECT
    run_id,
    tier,
    started_at::date AS run_date,
    overall_verdict,
    pass_count,
    warn_count,
    fail_count
FROM ops.audit_runs
ORDER BY started_at DESC
LIMIT 30;

-- Track migration
INSERT INTO ops.schema_migrations (filename, applied_at)
VALUES ('195_audit_findings_tables.up.sql', now());
