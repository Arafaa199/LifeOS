BEGIN;

DROP TRIGGER IF EXISTS trg_location_events_feed_status ON core.location_events;

DROP FUNCTION IF EXISTS core.update_feed_status_geofence();

DELETE FROM life.feed_status_live WHERE source = 'geofence';

DELETE FROM ops.schema_migrations WHERE filename = '193_geofence_feed_status.up.sql';

COMMIT;
