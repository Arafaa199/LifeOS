-- Migration: 026_github_activity (rollback)
-- Removes GitHub activity tracking

DROP FUNCTION IF EXISTS raw.ingest_github_event(TEXT, TEXT, TEXT, TIMESTAMPTZ, JSONB);
DROP VIEW IF EXISTS life.daily_productivity;
DROP TABLE IF EXISTS raw.github_events;
