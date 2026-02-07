-- Migration 166: Calendar bidirectional sync support
-- Adds sync columns for diff-based bidirectional sync between Nexus DB and iOS EventKit Calendar

-- 1. Add sync columns
ALTER TABLE raw.calendar_events
    ADD COLUMN IF NOT EXISTS sync_status VARCHAR(50) DEFAULT 'synced',
    ADD COLUMN IF NOT EXISTS eventkit_modified_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS origin VARCHAR(50) DEFAULT 'ios_eventkit';

-- 2. Backfill existing rows
UPDATE raw.calendar_events SET
    sync_status = 'synced',
    origin = 'ios_eventkit',
    last_seen_at = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP
WHERE sync_status IS NULL;

-- 3. Index on sync_status for pending operations
CREATE INDEX IF NOT EXISTS idx_calendar_events_sync_status
    ON raw.calendar_events (sync_status)
    WHERE deleted_at IS NULL;

-- 4. updated_at trigger (auto-set on UPDATE)
CREATE OR REPLACE FUNCTION raw.calendar_events_update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_calendar_events_updated_at ON raw.calendar_events;
CREATE TRIGGER trg_calendar_events_updated_at
    BEFORE UPDATE ON raw.calendar_events
    FOR EACH ROW
    EXECUTE FUNCTION raw.calendar_events_update_timestamp();

-- 5. Active calendar events view (excludes soft-deleted)
CREATE OR REPLACE VIEW life.v_active_calendar_events AS
SELECT
    id,
    event_id,
    title,
    start_at,
    end_at,
    is_all_day,
    calendar_name,
    location,
    notes,
    recurrence_rule,
    source,
    client_id,
    created_at,
    updated_at,
    sync_status,
    eventkit_modified_at,
    last_seen_at,
    origin
FROM raw.calendar_events
WHERE deleted_at IS NULL
  AND sync_status NOT IN ('deleted_remote', 'deleted_local');
