BEGIN;

INSERT INTO life.feed_status_live (source, expected_interval, events_today)
VALUES ('geofence', '24 hours'::interval, 0)
ON CONFLICT (source) DO NOTHING;

CREATE OR REPLACE FUNCTION core.update_feed_status_geofence()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO life.feed_status_live (source, last_event_at, events_today, expected_interval)
    VALUES ('geofence', now(), 1, '24 hours'::interval)
    ON CONFLICT (source) DO UPDATE SET
        last_event_at = now(),
        events_today = life.feed_status_live.events_today + 1;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_location_events_feed_status
    AFTER INSERT ON core.location_events
    FOR EACH ROW
    EXECUTE FUNCTION core.update_feed_status_geofence();

INSERT INTO ops.schema_migrations (filename)
VALUES ('193_geofence_feed_status.up.sql');

COMMIT;
