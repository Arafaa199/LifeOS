-- Migration: 062_raw_events_resolution.down.sql
-- Purpose: Remove raw_events resolution tracking

DROP VIEW IF EXISTS finance.v_raw_events_health;
DROP FUNCTION IF EXISTS finance.resolve_orphan_events();

DROP INDEX IF EXISTS finance.idx_raw_events_pending;
DROP INDEX IF EXISTS finance.idx_raw_events_resolution_status;
DROP INDEX IF EXISTS finance.idx_raw_events_source;

ALTER TABLE finance.raw_events DROP COLUMN IF EXISTS resolution_status;
ALTER TABLE finance.raw_events DROP COLUMN IF EXISTS resolution_reason;
ALTER TABLE finance.raw_events DROP COLUMN IF EXISTS resolved_at;
ALTER TABLE finance.raw_events DROP COLUMN IF EXISTS source;
