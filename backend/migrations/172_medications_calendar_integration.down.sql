-- Migration 172 Down: Remove medications-calendar integration

BEGIN;

DROP FUNCTION IF EXISTS life.toggle_reminder(TEXT, BOOLEAN);
DROP FUNCTION IF EXISTS life.upsert_reminder(TEXT, TEXT, TEXT, TIMESTAMPTZ, INT, TEXT, BOOLEAN);
DROP FUNCTION IF EXISTS life.get_calendar_entries(DATE, DATE, BOOLEAN);
DROP VIEW IF EXISTS life.v_calendar_combined;
DROP FUNCTION IF EXISTS health.update_dose_status(TEXT, DATE, TIME, TEXT, TIMESTAMPTZ);
DROP TRIGGER IF EXISTS trg_medications_updated_at ON health.medications;
DROP FUNCTION IF EXISTS health.update_medications_updated_at();

DROP INDEX IF EXISTS raw.idx_reminders_sync_pending;
ALTER TABLE raw.reminders DROP COLUMN IF EXISTS updated_at;
ALTER TABLE raw.reminders DROP COLUMN IF EXISTS sync_status;
ALTER TABLE raw.reminders DROP COLUMN IF EXISTS origin;

ALTER TABLE health.medications DROP COLUMN IF EXISTS toggled_in_app;
ALTER TABLE health.medications DROP COLUMN IF EXISTS updated_at;
ALTER TABLE health.medications DROP COLUMN IF EXISTS origin;

COMMIT;
