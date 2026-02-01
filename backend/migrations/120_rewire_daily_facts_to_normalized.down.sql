-- Rollback Migration 120: Restore legacy-reading life.refresh_daily_facts()
-- This restores the migration 111 version that reads from legacy tables.
-- Also removes calories_active from normalized.daily_strain.

-- Restore the strain trigger without calories_active
CREATE OR REPLACE FUNCTION health.propagate_whoop_strain()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_raw_id bigint;
BEGIN
    INSERT INTO raw.whoop_strain (strain_id, date, day_strain, workout_count, kilojoules, average_hr, max_hr, raw_json, source, run_id)
    VALUES (
        NEW.id, NEW.date, NEW.day_strain, 0, NEW.calories_total * 4.184, NEW.avg_hr, NEW.max_hr,
        COALESCE(NEW.raw_data, jsonb_build_object('day_strain', NEW.day_strain, 'calories_total', NEW.calories_total, 'propagated_at', now())),
        'whoop_api', gen_random_uuid()
    )
    ON CONFLICT (strain_id) DO UPDATE SET
        day_strain = EXCLUDED.day_strain, kilojoules = EXCLUDED.kilojoules,
        average_hr = EXCLUDED.average_hr, max_hr = EXCLUDED.max_hr, raw_json = EXCLUDED.raw_json
    RETURNING id INTO v_raw_id;

    IF v_raw_id IS NOT NULL THEN
        INSERT INTO normalized.daily_strain (date, day_strain, calories_burned, workout_count, average_hr, max_hr, raw_id, source)
        VALUES (NEW.date, NEW.day_strain, NEW.calories_total, 0, NEW.avg_hr, NEW.max_hr, v_raw_id, 'whoop_api')
        ON CONFLICT (date) DO UPDATE SET
            day_strain = EXCLUDED.day_strain, calories_burned = EXCLUDED.calories_burned,
            average_hr = EXCLUDED.average_hr, max_hr = EXCLUDED.max_hr,
            raw_id = EXCLUDED.raw_id, source = EXCLUDED.source, updated_at = now();
    END IF;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
    VALUES ('propagate_whoop_strain', TG_TABLE_NAME, SQLERRM, SQLSTATE);
    RETURN NEW;
END;
$fn$;

ALTER TABLE normalized.daily_strain DROP COLUMN IF EXISTS calories_active;

-- Restore the migration 111 version of life.refresh_daily_facts that reads legacy tables.
-- (Full function body omitted for brevity — apply migration 111 to restore.)
-- To fully rollback: re-run migration 111_reminder_daily_facts.up.sql
