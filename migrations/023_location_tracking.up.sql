-- Migration: 023_location_tracking
-- Adds location tracking tables and views for automated life signal capture
-- TASK-057: Location Tracking Automation

-- ============================================================================
-- life.locations - Store location events
-- ============================================================================

CREATE TABLE IF NOT EXISTS life.locations (
    id BIGSERIAL PRIMARY KEY,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    latitude NUMERIC(10, 7),
    longitude NUMERIC(10, 7),
    location_name TEXT,
    location_type TEXT CHECK (location_type IN ('home', 'work', 'gym', 'other')),
    event_type TEXT CHECK (event_type IN ('arrival', 'departure', 'check_in', 'poll')),
    source TEXT NOT NULL DEFAULT 'home_assistant',
    activity TEXT,
    accuracy_meters NUMERIC(6, 2),
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_locations_recorded_at ON life.locations(recorded_at DESC);
CREATE INDEX idx_locations_event_type ON life.locations(event_type);
CREATE INDEX idx_locations_location_type ON life.locations(location_type);

-- ============================================================================
-- life.daily_location_summary - Aggregate daily location metrics
-- ============================================================================

CREATE OR REPLACE VIEW life.daily_location_summary AS
WITH day_locations AS (
    SELECT
        (recorded_at AT TIME ZONE 'Asia/Dubai')::date AS day,
        recorded_at,
        location_type,
        event_type,
        LAG(recorded_at) OVER (PARTITION BY (recorded_at AT TIME ZONE 'Asia/Dubai')::date ORDER BY recorded_at) AS prev_recorded_at,
        LAG(location_type) OVER (PARTITION BY (recorded_at AT TIME ZONE 'Asia/Dubai')::date ORDER BY recorded_at) AS prev_location_type
    FROM life.locations
    WHERE recorded_at >= NOW() - INTERVAL '90 days'
),
time_segments AS (
    SELECT
        day,
        location_type,
        EXTRACT(EPOCH FROM (recorded_at - prev_recorded_at)) / 3600.0 AS hours_in_segment
    FROM day_locations
    WHERE prev_recorded_at IS NOT NULL
),
home_events AS (
    SELECT
        day,
        MIN(CASE WHEN event_type = 'departure' AND location_type = 'home' THEN recorded_at END) AS first_departure,
        MAX(CASE WHEN event_type = 'arrival' AND location_type = 'home' THEN recorded_at END) AS last_arrival
    FROM day_locations
    GROUP BY day
)
SELECT
    t.day,
    ROUND(COALESCE(SUM(CASE WHEN t.location_type = 'home' THEN t.hours_in_segment END), 0)::numeric, 2) AS hours_at_home,
    ROUND(COALESCE(SUM(CASE WHEN t.location_type != 'home' THEN t.hours_in_segment END), 0)::numeric, 2) AS hours_away,
    ROUND(COALESCE(SUM(CASE WHEN t.location_type = 'work' THEN t.hours_in_segment END), 0)::numeric, 2) AS hours_at_work,
    ROUND(COALESCE(SUM(CASE WHEN t.location_type = 'gym' THEN t.hours_in_segment END), 0)::numeric, 2) AS hours_at_gym,
    h.first_departure,
    h.last_arrival,
    COUNT(DISTINCT t.location_type) FILTER (WHERE t.location_type != 'home') AS unique_locations_visited
FROM time_segments t
LEFT JOIN home_events h ON t.day = h.day
GROUP BY t.day, h.first_departure, h.last_arrival
ORDER BY t.day DESC;

-- ============================================================================
-- Function to determine location type from coordinates
-- ============================================================================

CREATE OR REPLACE FUNCTION life.get_location_type(lat NUMERIC, lon NUMERIC, loc_name TEXT DEFAULT NULL)
RETURNS TEXT
LANGUAGE plpgsql
AS $function$
DECLARE
    -- Define home coordinates (Dubai - update with actual home coordinates)
    home_lat CONSTANT NUMERIC := 25.0657;  -- Replace with actual
    home_lon CONSTANT NUMERIC := 55.1713;  -- Replace with actual
    distance_km NUMERIC;
BEGIN
    -- Calculate approximate distance using Haversine formula (simplified)
    distance_km := 111.0 * SQRT(POWER(lat - home_lat, 2) + POWER((lon - home_lon) * COS(RADIANS(home_lat)), 2));

    -- Check if location name contains gym-related keywords
    IF loc_name IS NOT NULL AND loc_name ~* '(gym|fitness|workout|sport)' THEN
        RETURN 'gym';
    END IF;

    -- Within 100m of home
    IF distance_km < 0.1 THEN
        RETURN 'home';
    END IF;

    -- Otherwise classify as other
    RETURN 'other';
END;
$function$;

-- ============================================================================
-- Function to ingest location event
-- ============================================================================

CREATE OR REPLACE FUNCTION life.ingest_location(
    p_latitude NUMERIC,
    p_longitude NUMERIC,
    p_location_name TEXT DEFAULT NULL,
    p_event_type TEXT DEFAULT 'poll',
    p_activity TEXT DEFAULT NULL,
    p_source TEXT DEFAULT 'home_assistant'
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $function$
DECLARE
    v_location_type TEXT;
    v_id BIGINT;
BEGIN
    -- Determine location type
    v_location_type := life.get_location_type(p_latitude, p_longitude, p_location_name);

    INSERT INTO life.locations (
        recorded_at,
        latitude,
        longitude,
        location_name,
        location_type,
        event_type,
        source,
        activity
    ) VALUES (
        NOW(),
        p_latitude,
        p_longitude,
        p_location_name,
        v_location_type,
        p_event_type,
        p_source,
        p_activity
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$function$;

-- Grant permissions
GRANT SELECT, INSERT ON life.locations TO nexus;
GRANT USAGE, SELECT ON SEQUENCE life.locations_id_seq TO nexus;
GRANT SELECT ON life.daily_location_summary TO nexus;
GRANT EXECUTE ON FUNCTION life.get_location_type(NUMERIC, NUMERIC, TEXT) TO nexus;
GRANT EXECUTE ON FUNCTION life.ingest_location(NUMERIC, NUMERIC, TEXT, TEXT, TEXT, TEXT) TO nexus;

COMMENT ON TABLE life.locations IS 'Location events from device_tracker (arrival/departure/poll)';
COMMENT ON VIEW life.daily_location_summary IS 'Daily aggregated location metrics - time at home, away, work, gym';
COMMENT ON FUNCTION life.ingest_location IS 'Ingest a location event with automatic location type detection';
