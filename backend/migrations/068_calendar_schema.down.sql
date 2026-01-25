-- Migration 068 Rollback: Calendar Schema Prep

-- Drop view
DROP VIEW IF EXISTS life.v_daily_calendar_summary;

-- Drop indexes
DROP INDEX IF EXISTS idx_calendar_events_client_id;
DROP INDEX IF EXISTS idx_calendar_events_start_at;

-- Drop table
DROP TABLE IF EXISTS raw.calendar_events;
