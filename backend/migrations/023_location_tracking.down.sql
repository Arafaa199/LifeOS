-- Migration: 023_location_tracking (rollback)
-- Removes location tracking tables and views

DROP FUNCTION IF EXISTS life.ingest_location(NUMERIC, NUMERIC, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS life.get_location_type(NUMERIC, NUMERIC, TEXT);
DROP VIEW IF EXISTS life.daily_location_summary;
DROP TABLE IF EXISTS life.locations;
