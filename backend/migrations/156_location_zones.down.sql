-- Migration 156 DOWN: Revert location zone improvement

BEGIN;

-- Restore original get_location_type with old coordinates
CREATE OR REPLACE FUNCTION life.get_location_type(
    lat NUMERIC,
    lon NUMERIC,
    loc_name TEXT DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    home_lat CONSTANT NUMERIC := 25.0657;
    home_lon CONSTANT NUMERIC := 55.1713;
    distance_km NUMERIC;
BEGIN
    distance_km := 111.0 * SQRT(POWER(lat - home_lat, 2) + POWER((lon - home_lon) * COS(RADIANS(home_lat)), 2));
    IF loc_name IS NOT NULL AND loc_name ~* '(gym|fitness|workout|sport)' THEN
        RETURN 'gym';
    END IF;
    IF distance_km < 0.1 THEN
        RETURN 'home';
    END IF;
    RETURN 'other';
END;
$$ LANGUAGE plpgsql;

-- Restore original detect_location_zone (hardcoded)
CREATE OR REPLACE FUNCTION life.detect_location_zone(
    p_lat NUMERIC,
    p_lon NUMERIC
) RETURNS TEXT AS $$
DECLARE
    home_lat CONSTANT NUMERIC := 25.0781621;
    home_lon CONSTANT NUMERIC := 55.1526481;
    distance_km NUMERIC;
BEGIN
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

-- Restore original ingest_location (without zone name derivation)
CREATE OR REPLACE FUNCTION life.ingest_location(
    p_latitude NUMERIC,
    p_longitude NUMERIC,
    p_location_name TEXT DEFAULT NULL,
    p_event_type TEXT DEFAULT 'poll',
    p_activity TEXT DEFAULT NULL,
    p_source TEXT DEFAULT 'home_assistant'
) RETURNS BIGINT AS $$
DECLARE
    v_location_type TEXT;
    v_location_id BIGINT;
BEGIN
    v_location_type := life.get_location_type(p_latitude, p_longitude, p_location_name);
    INSERT INTO life.locations (
        recorded_at, latitude, longitude, location_name,
        location_type, event_type, source, activity
    ) VALUES (
        NOW(), p_latitude, p_longitude, p_location_name,
        v_location_type, p_event_type, p_source, p_activity
    ) RETURNING id INTO v_location_id;
    UPDATE life.feed_status_live
    SET last_event_at = NOW(),
        events_today = events_today + 1,
        last_updated = NOW()
    WHERE source = 'location';
    RETURN v_location_id;
END;
$$ LANGUAGE plpgsql;

-- Drop known zones table
DROP TABLE IF EXISTS life.known_zones;

-- Remove migration record
DELETE FROM ops.schema_migrations WHERE filename = '156_location_zones.up.sql';

COMMIT;
