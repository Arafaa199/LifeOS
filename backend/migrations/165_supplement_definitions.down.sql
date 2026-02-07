-- Rollback Migration 165

DROP FUNCTION IF EXISTS health.log_supplement_dose(INTEGER, TEXT, TEXT, TEXT);
DROP VIEW IF EXISTS health.v_todays_supplements;
DROP TRIGGER IF EXISTS trg_supplement_defs_updated ON health.supplement_definitions;
DROP FUNCTION IF EXISTS health.update_supplement_timestamp();
ALTER TABLE health.medications DROP COLUMN IF EXISTS supplement_id;
DROP TABLE IF EXISTS health.supplement_definitions;
DELETE FROM life.feed_status_live WHERE source = 'supplements';
