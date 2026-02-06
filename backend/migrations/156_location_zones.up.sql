-- Migration 156: Location Zone Improvement
-- Fix location_type detection by creating a known_zones table
-- and rewriting get_location_type() to match against it.
-- Root cause: old home coordinates (25.0657, 55.1713) were 1.4km off
-- from actual home (25.0781621, 55.1526481), so everything was 'other'.

BEGIN;

-- 1. Create known zones table
CREATE TABLE IF NOT EXISTS life.known_zones (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    zone_type TEXT NOT NULL CHECK (zone_type IN ('home', 'work', 'gym', 'other')),
    latitude NUMERIC(10, 7) NOT NULL,
    longitude NUMERIC(10, 7) NOT NULL,
    radius_km NUMERIC(5, 3) NOT NULL DEFAULT 0.15,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE life.known_zones IS 'Named geographic zones for location classification. Radius in km.';

-- 2. Seed known zones
INSERT INTO life.known_zones (name, zone_type, latitude, longitude, radius_km) VALUES
    ('Home', 'home', 25.0781621, 55.1526481, 0.15),
    ('Fitness First Motor City', 'gym', 25.0455, 55.1528, 0.20),
    ('Dubai Sports City', 'other', 25.0384, 55.1497, 0.50)
ON CONFLICT (name) DO NOTHING;

-- 3. Rewrite get_location_type to use known_zones table
CREATE OR REPLACE FUNCTION life.get_location_type(
    lat NUMERIC,
    lon NUMERIC,
    loc_name TEXT DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    matched_zone RECORD;
    distance_km NUMERIC;
BEGIN
    -- Check known zones (closest match within radius)
    SELECT kz.name, kz.zone_type,
           111.32 * SQRT(
               POWER(lat - kz.latitude, 2) +
               POWER((lon - kz.longitude) * COS(RADIANS(kz.latitude)), 2)
           ) AS dist
    INTO matched_zone
    FROM life.known_zones kz
    ORDER BY 111.32 * SQRT(
        POWER(lat - kz.latitude, 2) +
        POWER((lon - kz.longitude) * COS(RADIANS(kz.latitude)), 2)
    )
    LIMIT 1;

    IF matched_zone IS NOT NULL AND matched_zone.dist <= (
        SELECT radius_km FROM life.known_zones WHERE name = matched_zone.name
    ) THEN
        RETURN matched_zone.zone_type;
    END IF;

    -- Fallback: keyword matching on location_name
    IF loc_name IS NOT NULL AND loc_name ~* '(gym|fitness|workout|sport)' THEN
        RETURN 'gym';
    END IF;

    RETURN 'other';
END;
$$ LANGUAGE plpgsql STABLE;

-- 4. Create detect_location_zone to return zone NAME (not just type)
CREATE OR REPLACE FUNCTION life.detect_location_zone(
    p_lat NUMERIC,
    p_lon NUMERIC
) RETURNS TEXT AS $$
DECLARE
    matched_zone RECORD;
BEGIN
    SELECT kz.name, kz.zone_type,
           111.32 * SQRT(
               POWER(p_lat - kz.latitude, 2) +
               POWER((p_lon - kz.longitude) * COS(RADIANS(kz.latitude)), 2)
           ) AS dist,
           kz.radius_km
    INTO matched_zone
    FROM life.known_zones kz
    ORDER BY 111.32 * SQRT(
        POWER(p_lat - kz.latitude, 2) +
        POWER((p_lon - kz.longitude) * COS(RADIANS(kz.latitude)), 2)
    )
    LIMIT 1;

    IF matched_zone IS NOT NULL AND matched_zone.dist <= matched_zone.radius_km THEN
        RETURN matched_zone.name;
    ELSIF matched_zone IS NOT NULL AND matched_zone.dist < 50 THEN
        RETURN 'local';
    ELSE
        RETURN 'away';
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;

-- 5. Rewrite ingest_location to also set location_name from zone detection
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
    v_location_name TEXT;
    v_location_id BIGINT;
BEGIN
    v_location_type := life.get_location_type(p_latitude, p_longitude, p_location_name);

    -- Derive location_name from zone if HA sends 'unavailable' or NULL
    IF p_location_name IS NULL OR p_location_name IN ('unavailable', 'unknown', '') THEN
        v_location_name := life.detect_location_zone(p_latitude, p_longitude);
    ELSE
        v_location_name := p_location_name;
    END IF;

    INSERT INTO life.locations (
        recorded_at, latitude, longitude, location_name,
        location_type, event_type, source, activity
    ) VALUES (
        NOW(), p_latitude, p_longitude, v_location_name,
        v_location_type, p_event_type, p_source, p_activity
    ) RETURNING id INTO v_location_id;

    -- Update feed status
    UPDATE life.feed_status_live
    SET last_event_at = NOW(),
        events_today = events_today + 1,
        last_updated = NOW()
    WHERE source = 'location';

    RETURN v_location_id;
END;
$$ LANGUAGE plpgsql;

-- 6. Backfill: fix all existing location records
-- Update location_type using new get_location_type (correct coordinates)
UPDATE life.locations
SET location_type = life.get_location_type(latitude, longitude, location_name)
WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

-- Update location_name where it was 'unavailable'
UPDATE life.locations
SET location_name = life.detect_location_zone(latitude, longitude)
WHERE (location_name IS NULL OR location_name IN ('unavailable', 'unknown', ''))
  AND latitude IS NOT NULL AND longitude IS NOT NULL;

-- 7. Log migration
INSERT INTO ops.schema_migrations (filename) VALUES
    ('156_location_zones.up.sql')
ON CONFLICT (filename) DO NOTHING;

COMMIT;
