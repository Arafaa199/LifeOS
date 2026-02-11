-- Migration 191: Minimum duration filter for drive-bys + BJJ detect uses location_events
-- - process_location_update: exits with duration < 5 min are treated as drive-bys (cleaned up)
-- - BJJ auto-detect should query core.location_events instead of life.location_history

BEGIN;

CREATE OR REPLACE FUNCTION core.process_location_update(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_event_type TEXT DEFAULT 'poll',
    p_location_name TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    result JSONB;
    v_zone_id INTEGER;
    v_zone_name TEXT;
    v_zone_category TEXT;
    v_last_type TEXT;
    v_last_ts TIMESTAMPTZ;
    v_enter_id INTEGER;
    v_duration INTEGER;
    v_min_duration CONSTANT INTEGER := 5; -- minutes; exits shorter than this are drive-bys
BEGIN
    -- ═══════════════════════════════════════════════════
    -- GEOFENCE EVENTS: explicit enter/exit with zone name
    -- ═══════════════════════════════════════════════════
    IF p_event_type IN ('enter', 'exit') AND p_location_name IS NOT NULL THEN

        SELECT id, name, category INTO v_zone_id, v_zone_name, v_zone_category
        FROM core.known_locations
        WHERE name = p_location_name AND is_active
        LIMIT 1;

        IF v_zone_id IS NULL THEN
            RETURN jsonb_build_object(
                'matched_zones', '[]'::jsonb,
                'enter_events', '[]'::jsonb,
                'exit_events', '[]'::jsonb
            );
        END IF;

        -- Last event for this zone
        SELECT le.id, le.event_type, le.timestamp
        INTO v_enter_id, v_last_type, v_last_ts
        FROM core.location_events le
        WHERE le.location_id = v_zone_id
        ORDER BY le.timestamp DESC
        LIMIT 1;

        IF p_event_type = 'enter' THEN
            IF v_last_type IS NULL OR v_last_type = 'exit' THEN
                INSERT INTO core.location_events (location_id, event_type)
                VALUES (v_zone_id, 'enter');

                RETURN jsonb_build_object(
                    'matched_zones', jsonb_build_array(jsonb_build_object(
                        'location_id', v_zone_id, 'name', v_zone_name,
                        'category', v_zone_category, 'distance_meters', 0
                    )),
                    'enter_events', jsonb_build_array(jsonb_build_object(
                        'location_id', v_zone_id, 'event', 'enter'
                    )),
                    'exit_events', '[]'::jsonb
                );
            END IF;

        ELSIF p_event_type = 'exit' THEN
            IF v_last_type = 'enter' THEN
                v_duration := EXTRACT(EPOCH FROM (now() - v_last_ts))::integer / 60;

                -- Drive-by filter: if too short, delete the enter and skip exit
                IF v_duration < v_min_duration THEN
                    DELETE FROM core.location_events WHERE id = v_enter_id;
                    RETURN jsonb_build_object(
                        'matched_zones', '[]'::jsonb,
                        'enter_events', '[]'::jsonb,
                        'exit_events', '[]'::jsonb,
                        'filtered', jsonb_build_object(
                            'reason', 'drive_by',
                            'location_id', v_zone_id,
                            'duration_minutes', v_duration
                        )
                    );
                END IF;

                INSERT INTO core.location_events (location_id, event_type, duration_minutes)
                VALUES (v_zone_id, 'exit', v_duration);

                RETURN jsonb_build_object(
                    'matched_zones', '[]'::jsonb,
                    'enter_events', '[]'::jsonb,
                    'exit_events', jsonb_build_array(jsonb_build_object(
                        'location_id', v_zone_id, 'event', 'exit',
                        'duration_minutes', v_duration
                    ))
                );
            END IF;
        END IF;

        RETURN jsonb_build_object(
            'matched_zones', '[]'::jsonb,
            'enter_events', '[]'::jsonb,
            'exit_events', '[]'::jsonb
        );
    END IF;

    -- ═══════════════════════════════════════════════════
    -- POLL EVENTS: proximity-based enter/exit
    -- ═══════════════════════════════════════════════════
    WITH matches AS (
        SELECT * FROM core.match_location(p_lat, p_lng)
    ),
    last_events AS (
        SELECT DISTINCT ON (le.location_id)
            le.id AS event_id, le.location_id,
            le.event_type AS last_type, le.timestamp AS last_ts
        FROM core.location_events le
        WHERE le.location_id IN (SELECT location_id FROM matches)
           OR le.location_id IN (
               SELECT le2.location_id FROM core.location_events le2
               WHERE le2.event_type = 'enter'
                 AND le2.timestamp > now() - INTERVAL '24 hours'
           )
        ORDER BY le.location_id, le.timestamp DESC
    ),
    enters AS (
        INSERT INTO core.location_events (location_id, event_type)
        SELECT m.location_id, 'enter'
        FROM matches m
        LEFT JOIN last_events le ON le.location_id = m.location_id
        WHERE le.location_id IS NULL OR le.last_type = 'exit'
        RETURNING location_id, event_type, timestamp
    ),
    -- Compute exits with duration, filtering drive-bys
    exit_candidates AS (
        SELECT
            le.location_id,
            le.event_id AS enter_event_id,
            EXTRACT(EPOCH FROM (now() - le.last_ts))::integer / 60 AS dur
        FROM last_events le
        WHERE le.last_type = 'enter'
          AND le.location_id NOT IN (SELECT location_id FROM matches)
    ),
    -- Delete drive-by enters (duration < 5 min)
    deleted_drivebys AS (
        DELETE FROM core.location_events
        WHERE id IN (SELECT enter_event_id FROM exit_candidates WHERE dur < 5)
        RETURNING id
    ),
    -- Only insert real exits
    exits AS (
        INSERT INTO core.location_events (location_id, event_type, duration_minutes)
        SELECT ec.location_id, 'exit', ec.dur
        FROM exit_candidates ec
        WHERE ec.dur >= 5
        RETURNING location_id, event_type, duration_minutes
    )
    SELECT jsonb_build_object(
        'matched_zones', COALESCE(
            (SELECT json_agg(json_build_object(
                'location_id', m.location_id, 'name', m.name,
                'category', m.category,
                'distance_meters', ROUND(m.distance_meters::numeric, 1)
            ))::jsonb FROM matches m),
            '[]'::jsonb
        ),
        'enter_events', COALESCE(
            (SELECT json_agg(json_build_object(
                'location_id', location_id, 'event', event_type
            ))::jsonb FROM enters),
            '[]'::jsonb
        ),
        'exit_events', COALESCE(
            (SELECT json_agg(json_build_object(
                'location_id', location_id, 'event', event_type,
                'duration_minutes', duration_minutes
            ))::jsonb FROM exits),
            '[]'::jsonb
        )
    ) INTO result;

    RETURN COALESCE(result, jsonb_build_object(
        'matched_zones', '[]'::jsonb,
        'enter_events', '[]'::jsonb,
        'exit_events', '[]'::jsonb
    ));
END;
$$;

COMMENT ON FUNCTION core.process_location_update IS
    'v2: Unified location processor with 5-min minimum duration filter for drive-by prevention';

INSERT INTO ops.schema_migrations (filename)
VALUES ('191_geofence_min_duration_bjj_detect.up.sql')
ON CONFLICT (filename) DO NOTHING;

COMMIT;
