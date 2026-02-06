-- Rollback: 154_weather_and_location

ALTER TABLE life.daily_facts 
DROP COLUMN IF EXISTS weather_temp_high,
DROP COLUMN IF EXISTS weather_temp_low,
DROP COLUMN IF EXISTS weather_condition,
DROP COLUMN IF EXISTS weather_humidity,
DROP COLUMN IF EXISTS weather_uv_index,
DROP COLUMN IF EXISTS hours_at_home,
DROP COLUMN IF EXISTS hours_away,
DROP COLUMN IF EXISTS primary_location;

DROP TABLE IF EXISTS life.weather_daily;
DROP FUNCTION IF EXISTS life.update_daily_facts_weather(DATE);
DROP FUNCTION IF EXISTS life.update_daily_facts_location(DATE);
DROP FUNCTION IF EXISTS life.detect_location_zone(NUMERIC, NUMERIC);
