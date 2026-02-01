-- Migration 117: Reminders bidirectional sync support
-- Adds sync columns for diff-based bidirectional sync between Nexus DB and Apple Reminders

-- 1. Add sync columns
ALTER TABLE raw.reminders
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS sync_status VARCHAR(20) DEFAULT 'synced',
    ADD COLUMN IF NOT EXISTS eventkit_modified_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS origin VARCHAR(20) DEFAULT 'eventkit';

-- 2. updated_at trigger (auto-set on UPDATE)
CREATE OR REPLACE FUNCTION raw.set_reminders_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_reminders_updated_at ON raw.reminders;
CREATE TRIGGER trg_reminders_updated_at
    BEFORE UPDATE ON raw.reminders
    FOR EACH ROW
    EXECUTE FUNCTION raw.set_reminders_updated_at();

-- 3. Index on sync_status for pending operations
CREATE INDEX IF NOT EXISTS idx_reminders_sync_status
    ON raw.reminders (sync_status)
    WHERE deleted_at IS NULL;

-- 4. Active reminders view (excludes soft-deleted)
CREATE OR REPLACE VIEW life.v_active_reminders AS
SELECT
    id,
    reminder_id,
    title,
    notes,
    due_date,
    is_completed,
    completed_date,
    priority,
    list_name,
    source,
    client_id,
    created_at,
    updated_at,
    sync_status,
    eventkit_modified_at,
    last_seen_at,
    origin
FROM raw.reminders
WHERE deleted_at IS NULL
  AND sync_status NOT IN ('deleted_remote', 'deleted_local');

-- 5. Backfill existing rows
UPDATE raw.reminders SET
    sync_status = 'synced',
    origin = 'eventkit',
    last_seen_at = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP
WHERE sync_status IS NULL OR origin IS NULL;
