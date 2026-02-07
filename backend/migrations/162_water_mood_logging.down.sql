-- Rollback: 162_water_mood_logging

DROP TRIGGER IF EXISTS trg_water_log_feed_status ON nutrition.water_log;
DROP FUNCTION IF EXISTS nutrition.update_water_feed_status();
DROP VIEW IF EXISTS nutrition.v_daily_water_summary;
DROP TABLE IF EXISTS nutrition.water_log;

DROP TRIGGER IF EXISTS trg_mood_log_feed_status ON raw.mood_log;
DROP FUNCTION IF EXISTS raw.update_mood_feed_status();
DROP VIEW IF EXISTS raw.v_daily_mood_summary;
DROP TABLE IF EXISTS raw.mood_log;

DELETE FROM life.feed_status_live WHERE source IN ('water', 'mood');

-- Note: Columns added to daily_facts are NOT removed to preserve data
