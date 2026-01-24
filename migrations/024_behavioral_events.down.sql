-- Migration: 024_behavioral_events (rollback)
-- Removes behavioral events tables and views

DROP TRIGGER IF EXISTS tr_calculate_tv_duration ON life.behavioral_events;
DROP FUNCTION IF EXISTS life.log_tv_session_end();
DROP FUNCTION IF EXISTS life.ingest_behavioral_event(TEXT, TEXT, JSONB);
DROP VIEW IF EXISTS life.daily_behavioral_summary;
DROP TABLE IF EXISTS life.behavioral_events;
