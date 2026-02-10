-- Migration 172: Medications ↔ Calendar Integration
--
-- Surfaces medication schedules in the calendar view and allows
-- dose status updates from the app (bidirectional).
--
-- Changes:
--   (a) Add origin column to medications (healthkit vs manual)
--   (b) Add medication_id reference to calendar events view
--   (c) Create function to generate calendar entries from medication schedules
--   (d) Create function to update dose status from iOS app
--   (e) Create combined calendar+medications view for the iOS endpoint

BEGIN;

-- =============================================================================
-- 1. ENHANCE MEDICATIONS TABLE FOR BIDIRECTIONAL SUPPORT
-- =============================================================================

-- Origin: was this dose discovered from HealthKit or created manually in-app?
ALTER TABLE health.medications
ADD COLUMN IF NOT EXISTS origin TEXT NOT NULL DEFAULT 'healthkit';

-- Allow app-side dose status updates
ALTER TABLE health.medications
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- Track which doses the user manually toggled in the Nexus app
ALTER TABLE health.medications
ADD COLUMN IF NOT EXISTS toggled_in_app BOOLEAN DEFAULT FALSE;

-- Trigger for auto-updating updated_at
CREATE OR REPLACE FUNCTION health.update_medications_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_medications_updated_at ON health.medications;
CREATE TRIGGER trg_medications_updated_at
    BEFORE UPDATE ON health.medications
    FOR EACH ROW EXECUTE FUNCTION health.update_medications_updated_at();

-- =============================================================================
-- 2. DOSE STATUS UPDATE FUNCTION (called from iOS via webhook)
-- =============================================================================

CREATE OR REPLACE FUNCTION health.update_dose_status(
    p_medication_id TEXT,
    p_scheduled_date DATE,
    p_scheduled_time TIME DEFAULT NULL,
    p_new_status TEXT DEFAULT 'taken',
    p_taken_at TIMESTAMPTZ DEFAULT NOW()
)
RETURNS TABLE(
    dose_id INT,
    medication_name TEXT,
    old_status TEXT,
    new_status TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    rec RECORD;
BEGIN
    -- Validate status
    IF p_new_status NOT IN ('taken', 'skipped', 'scheduled') THEN
        RAISE EXCEPTION 'Invalid status: %. Must be taken, skipped, or scheduled.', p_new_status;
    END IF;

    -- Find and update the dose
    FOR rec IN
        UPDATE health.medications
        SET status = p_new_status,
            taken_at = CASE
                WHEN p_new_status = 'taken' THEN COALESCE(p_taken_at, NOW())
                ELSE NULL
            END,
            toggled_in_app = TRUE
        WHERE medication_id = p_medication_id
          AND scheduled_date = p_scheduled_date
          AND (p_scheduled_time IS NULL OR scheduled_time = p_scheduled_time)
        RETURNING id, health.medications.medication_name, health.medications.status
    LOOP
        RETURN QUERY SELECT rec.id, rec.medication_name,
            rec.status, p_new_status;
    END LOOP;

    -- If no rows matched, insert a manual dose entry
    IF NOT FOUND THEN
        INSERT INTO health.medications (
            medication_id, medication_name, scheduled_date, scheduled_time,
            status, taken_at, source, origin, toggled_in_app
        ) VALUES (
            p_medication_id,
            p_medication_id,  -- use ID as name if we don't have the name
            p_scheduled_date,
            p_scheduled_time,
            p_new_status,
            CASE WHEN p_new_status = 'taken' THEN COALESCE(p_taken_at, NOW()) ELSE NULL END,
            'ios_app',
            'manual',
            TRUE
        )
        RETURNING id, health.medications.medication_name INTO rec;

        RETURN QUERY SELECT rec.id, rec.medication_name, 'new'::TEXT, p_new_status;
    END IF;
END;
$$;

-- =============================================================================
-- 3. COMBINED CALENDAR VIEW (events + reminders + medications)
-- =============================================================================

CREATE OR REPLACE VIEW life.v_calendar_combined AS
-- Calendar events
SELECT
    'event' AS entry_type,
    event_id AS entry_id,
    title,
    start_at,
    end_at,
    is_all_day,
    calendar_name AS source_name,
    location,
    notes,
    NULL::TEXT AS status,
    NULL::TEXT AS medication_id
FROM raw.calendar_events
WHERE deleted_at IS NULL
  AND sync_status != 'deleted_remote'

UNION ALL

-- Medications as time-blocked entries
SELECT
    'medication' AS entry_type,
    'med_' || id::TEXT AS entry_id,
    medication_name || ' (' || COALESCE(dose_quantity::TEXT || ' ' || COALESCE(dose_unit, ''), 'dose') || ')' AS title,
    (scheduled_date || 'T' || COALESCE(scheduled_time::TEXT, '09:00:00'))::TIMESTAMPTZ AS start_at,
    (scheduled_date || 'T' || COALESCE(scheduled_time::TEXT, '09:00:00'))::TIMESTAMPTZ + INTERVAL '5 minutes' AS end_at,
    FALSE AS is_all_day,
    'Medications' AS source_name,
    NULL AS location,
    'Status: ' || status AS notes,
    status,
    medication_id
FROM health.medications
WHERE scheduled_date >= CURRENT_DATE - INTERVAL '7 days';

COMMENT ON VIEW life.v_calendar_combined IS 'Unified calendar view: events + medications for iOS calendar display';

-- =============================================================================
-- 4. CALENDAR ENDPOINT FUNCTION (returns combined data for a date range)
-- =============================================================================

CREATE OR REPLACE FUNCTION life.get_calendar_entries(
    p_start DATE,
    p_end DATE,
    p_include_medications BOOLEAN DEFAULT TRUE
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'success', TRUE,
        'events', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'entry_type', entry_type,
                'entry_id', entry_id,
                'title', title,
                'start_at', start_at,
                'end_at', end_at,
                'is_all_day', is_all_day,
                'source_name', source_name,
                'location', location,
                'notes', notes,
                'status', status,
                'medication_id', medication_id
            ) ORDER BY start_at)
            FROM life.v_calendar_combined
            WHERE start_at::date BETWEEN p_start AND p_end
              AND (p_include_medications OR entry_type != 'medication')
        ), '[]'::jsonb),
        'count', (
            SELECT COUNT(*)
            FROM life.v_calendar_combined
            WHERE start_at::date BETWEEN p_start AND p_end
              AND (p_include_medications OR entry_type != 'medication')
        )
    ) INTO result;

    RETURN result;
END;
$$;

-- =============================================================================
-- 5. REMINDER BIDIRECTIONAL SUPPORT
--
-- Add columns to raw.reminders for app-side CRUD
-- =============================================================================

ALTER TABLE raw.reminders
ADD COLUMN IF NOT EXISTS origin TEXT NOT NULL DEFAULT 'eventkit';

ALTER TABLE raw.reminders
ADD COLUMN IF NOT EXISTS sync_status TEXT NOT NULL DEFAULT 'synced';

ALTER TABLE raw.reminders
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- Index for pending sync items
CREATE INDEX IF NOT EXISTS idx_reminders_sync_pending
    ON raw.reminders (sync_status)
    WHERE sync_status IN ('pending_push', 'pending_delete');

-- Function to create/update reminders from the app
CREATE OR REPLACE FUNCTION life.upsert_reminder(
    p_reminder_id TEXT,
    p_title TEXT,
    p_notes TEXT DEFAULT NULL,
    p_due_date TIMESTAMPTZ DEFAULT NULL,
    p_priority INT DEFAULT 0,
    p_list_name TEXT DEFAULT NULL,
    p_is_completed BOOLEAN DEFAULT FALSE
)
RETURNS TABLE(reminder_id TEXT, was_created BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
    existing RECORD;
BEGIN
    SELECT * INTO existing FROM raw.reminders
    WHERE raw.reminders.reminder_id = p_reminder_id;

    IF existing IS NOT NULL THEN
        UPDATE raw.reminders
        SET title = COALESCE(p_title, existing.title),
            notes = p_notes,
            due_date = p_due_date,
            priority = p_priority,
            list_name = COALESCE(p_list_name, existing.list_name),
            is_completed = p_is_completed,
            completed_date = CASE WHEN p_is_completed THEN NOW() ELSE NULL END,
            sync_status = 'pending_push',
            updated_at = NOW()
        WHERE raw.reminders.reminder_id = p_reminder_id;

        RETURN QUERY SELECT p_reminder_id, FALSE;
    ELSE
        INSERT INTO raw.reminders (
            reminder_id, title, notes, due_date, priority,
            list_name, is_completed, source, origin, sync_status
        ) VALUES (
            COALESCE(p_reminder_id, 'nexus_' || gen_random_uuid()::TEXT),
            p_title, p_notes, p_due_date, p_priority,
            p_list_name, p_is_completed, 'ios_app', 'nexus', 'pending_push'
        );

        RETURN QUERY SELECT COALESCE(p_reminder_id, 'nexus_' || gen_random_uuid()::TEXT), TRUE;
    END IF;
END;
$$;

-- Function to toggle reminder completion
CREATE OR REPLACE FUNCTION life.toggle_reminder(
    p_reminder_id TEXT,
    p_completed BOOLEAN DEFAULT NULL
)
RETURNS TABLE(reminder_id TEXT, is_completed BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
    new_status BOOLEAN;
BEGIN
    IF p_completed IS NOT NULL THEN
        new_status := p_completed;
    ELSE
        SELECT NOT r.is_completed INTO new_status
        FROM raw.reminders r
        WHERE r.reminder_id = p_reminder_id;
    END IF;

    UPDATE raw.reminders
    SET is_completed = new_status,
        completed_date = CASE WHEN new_status THEN NOW() ELSE NULL END,
        sync_status = 'pending_push',
        updated_at = NOW()
    WHERE raw.reminders.reminder_id = p_reminder_id;

    RETURN QUERY SELECT p_reminder_id, new_status;
END;
$$;

COMMIT;
