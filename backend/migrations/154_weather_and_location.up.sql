-- Migration 154: Add weather data and improve location tracking
-- Weather from OpenWeatherMap API, attached to daily_facts

-- Add weather columns to daily_facts
ALTER TABLE life.daily_facts 
ADD COLUMN IF NOT EXISTS weather_temp_high NUMERIC(4,1),
ADD COLUMN IF NOT EXISTS weather_temp_low NUMERIC(4,1),
ADD COLUMN IF NOT EXISTS weather_condition TEXT,
ADD COLUMN IF NOT EXISTS weather_humidity INT,
ADD COLUMN IF NOT EXISTS weather_uv_index NUMERIC(3,1);

-- Add location summary columns to daily_facts
ALTER TABLE life.daily_facts
ADD COLUMN IF NOT EXISTS hours_at_home NUMERIC(4,1),
ADD COLUMN IF NOT EXISTS hours_away NUMERIC(4,1),
ADD COLUMN IF NOT EXISTS primary_location TEXT;

-- Weather history table for detailed tracking
CREATE TABLE IF NOT EXISTS life.weather_daily (
    date DATE PRIMARY KEY,
    temp_high NUMERIC(4,1),
    temp_low NUMERIC(4,1),
    temp_avg NUMERIC(4,1),
    condition TEXT,
    condition_code INT,
    humidity INT,
    wind_speed NUMERIC(5,2),
    uv_index NUMERIC(3,1),
    precipitation_mm NUMERIC(5,2),
    sunrise TIMESTAMPTZ,
    sunset TIMESTAMPTZ,
    raw_json JSONB,
    fetched_at TIMESTAMPTZ DEFAULT NOW()
);

GRANT SELECT, INSERT, UPDATE ON life.weather_daily TO nexus;

-- Function to update daily_facts with weather
CREATE OR REPLACE FUNCTION life.update_daily_facts_weather(p_date DATE)
RETURNS VOID AS $$
BEGIN
    UPDATE life.daily_facts df
    SET 
        weather_temp_high = w.temp_high,
        weather_temp_low = w.temp_low,
        weather_condition = w.condition,
        weather_humidity = w.humidity,
        weather_uv_index = w.uv_index
    FROM life.weather_daily w
    WHERE df.day = p_date AND w.date = p_date;
END;
$$ LANGUAGE plpgsql;

-- Function to update daily_facts with location summary
CREATE OR REPLACE FUNCTION life.update_daily_facts_location(p_date DATE)
RETURNS VOID AS $$
BEGIN
    UPDATE life.daily_facts df
    SET 
        hours_at_home = ls.hours_at_home,
        hours_away = ls.hours_away,
        primary_location = CASE 
            WHEN ls.hours_at_home >= ls.hours_away THEN 'home'
            WHEN ls.hours_at_work > 4 THEN 'work'
            WHEN ls.hours_at_gym > 0 THEN 'active'
            ELSE 'out'
        END
    FROM life.daily_location_summary ls
    WHERE df.day = p_date AND ls.day = p_date;
END;
$$ LANGUAGE plpgsql;

-- Improve location zone detection: map coordinates to known zones
CREATE OR REPLACE FUNCTION life.detect_location_zone(
    p_lat NUMERIC,
    p_lon NUMERIC
) RETURNS TEXT AS $$
DECLARE
    -- Dubai coordinates (approximate home location from data)
    home_lat CONSTANT NUMERIC := 25.0781621;
    home_lon CONSTANT NUMERIC := 55.1526481;
    distance_km NUMERIC;
BEGIN
    -- Haversine distance calculation (simplified)
    distance_km := 111.32 * SQRT(
        POWER(p_lat - home_lat, 2) + 
        POWER((p_lon - home_lon) * COS(RADIANS(home_lat)), 2)
    );
    
    IF distance_km < 0.1 THEN
        RETURN 'home';
    ELSIF distance_km < 50 THEN
        RETURN 'local';
    ELSE
        RETURN 'away';
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Update existing locations with detected zones
UPDATE life.locations
SET location_type = life.detect_location_zone(latitude, longitude)
WHERE location_name = 'unavailable' OR location_type = 'other';

COMMENT ON TABLE life.weather_daily IS 'Daily weather data for Dubai, fetched from weather API';
