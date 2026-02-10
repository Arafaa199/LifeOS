-- Migration 183: General-purpose geofence system
-- core.known_locations, core.match_location(), core.location_events

BEGIN;

-- 1. core.known_locations
CREATE TABLE core.known_locations (
    id             SERIAL PRIMARY KEY,
    name           TEXT NOT NULL UNIQUE,
    category       TEXT NOT NULL CHECK (category IN ('gym', 'work', 'home', 'other')),
    lat            DOUBLE PRECISION NOT NULL,
    lng            DOUBLE PRECISION NOT NULL,
    radius_meters  INTEGER NOT NULL DEFAULT 150,
    metadata       JSONB NOT NULL DEFAULT '{}',
    is_active      BOOLEAN NOT NULL DEFAULT true,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed gym from BJJ auto-detect workflow coordinates
INSERT INTO core.known_locations (name, category, lat, lng, radius_meters)
VALUES ('gym', 'gym', 25.07822362022749, 55.14869064417944, 150);

-- 2. core.match_location(lat, lng)
CREATE OR REPLACE FUNCTION core.match_location(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION
)
RETURNS TABLE (
    location_id    INTEGER,
    name           TEXT,
    category       TEXT,
    distance_meters DOUBLE PRECISION,
    radius_meters  INTEGER
)
LANGUAGE sql STABLE
AS $$
    SELECT
        kl.id,
        kl.name,
        kl.category,
        6371000.0 * acos(
            LEAST(1.0, GREATEST(-1.0,
                cos(radians(p_lat)) * cos(radians(kl.lat)) *
                cos(radians(kl.lng) - radians(p_lng)) +
                sin(radians(p_lat)) * sin(radians(kl.lat))
            ))
        ),
        kl.radius_meters
    FROM core.known_locations kl
    WHERE kl.is_active
      AND 6371000.0 * acos(
            LEAST(1.0, GREATEST(-1.0,
                cos(radians(p_lat)) * cos(radians(kl.lat)) *
                cos(radians(kl.lng) - radians(p_lng)) +
                sin(radians(p_lat)) * sin(radians(kl.lat))
            ))
          ) <= kl.radius_meters
    ORDER BY 4
$$;

-- 3. core.location_events
CREATE TABLE core.location_events (
    id               SERIAL PRIMARY KEY,
    location_id      INTEGER NOT NULL REFERENCES core.known_locations(id),
    event_type       TEXT NOT NULL CHECK (event_type IN ('enter', 'exit')),
    timestamp        TIMESTAMPTZ NOT NULL DEFAULT now(),
    duration_minutes INTEGER
);

CREATE INDEX idx_location_events_loc_ts
    ON core.location_events (location_id, timestamp DESC);

COMMIT;
