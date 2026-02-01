-- Rollback Migration 117: Reminders bidirectional sync support

DROP VIEW IF EXISTS life.v_active_reminders;
DROP TRIGGER IF EXISTS trg_reminders_updated_at ON raw.reminders;
DROP FUNCTION IF EXISTS raw.set_reminders_updated_at();
DROP INDEX IF EXISTS raw.idx_reminders_sync_status;

ALTER TABLE raw.reminders
    DROP COLUMN IF EXISTS updated_at,
    DROP COLUMN IF EXISTS deleted_at,
    DROP COLUMN IF EXISTS sync_status,
    DROP COLUMN IF EXISTS eventkit_modified_at,
    DROP COLUMN IF EXISTS last_seen_at,
    DROP COLUMN IF EXISTS origin;
