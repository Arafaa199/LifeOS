DROP VIEW IF EXISTS ops.v_audit_trend;
DROP VIEW IF EXISTS ops.v_audit_open_issues;
DROP VIEW IF EXISTS ops.v_latest_audit;
DROP TABLE IF EXISTS ops.audit_findings;
DROP TABLE IF EXISTS ops.audit_runs;

DELETE FROM ops.schema_migrations WHERE filename = '195_audit_findings_tables.up.sql';
