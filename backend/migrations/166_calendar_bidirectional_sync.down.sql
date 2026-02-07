-- Migration 166 down: Remove calendar bidirectional sync columns

DROP VIEW IF EXISTS life.v_active_calendar_events;
DROP TRIGGER IF EXISTS trg_calendar_events_updated_at ON raw.calendar_events;
DROP FUNCTION IF EXISTS raw.calendar_events_update_timestamp();
DROP INDEX IF EXISTS raw.idx_calendar_events_sync_status;

ALTER TABLE raw.calendar_events
    DROP COLUMN IF EXISTS sync_status,
    DROP COLUMN IF EXISTS eventkit_modified_at,
    DROP COLUMN IF EXISTS updated_at,
    DROP COLUMN IF EXISTS deleted_at,
    DROP COLUMN IF EXISTS last_seen_at,
    DROP COLUMN IF EXISTS origin;
