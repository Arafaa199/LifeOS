-- Rollback: 155_screen_time

ALTER TABLE life.daily_facts
DROP COLUMN IF EXISTS screen_time_hours;

DROP FUNCTION IF EXISTS life.update_daily_facts_screen_time(DATE);
DROP TABLE IF EXISTS life.screen_time_daily;

DELETE FROM life.feed_status_live WHERE source = 'screen_time';
