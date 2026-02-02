-- Migration 136: Create schema_migrations tracking table
-- Tracks which migration files have been applied to prevent re-runs and skips.

CREATE TABLE IF NOT EXISTS ops.schema_migrations (
    filename    TEXT PRIMARY KEY,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    checksum    TEXT,
    duration_ms INT
);

COMMENT ON TABLE ops.schema_migrations IS
'Tracks applied migration files. Used by backend/migrate.sh to determine pending migrations.
Migration 136: Initial creation. All pre-existing migrations baselined on first run.';
