-- Rollback Migration 178: Remove BJJ sessions table

DROP FUNCTION IF EXISTS health.get_bjj_streaks();
DROP FUNCTION IF EXISTS health.update_bjj_sessions_updated_at() CASCADE;
DROP TABLE IF EXISTS health.bjj_sessions;
