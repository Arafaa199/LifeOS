BEGIN;

-- Rollback migration 157: Remove life.listening_events table and feed status

DROP TRIGGER IF EXISTS trg_listening_events_feed ON life.listening_events;
DROP FUNCTION IF EXISTS life.update_music_feed_status();
DROP TABLE IF EXISTS life.listening_events;
DELETE FROM life.feed_status_live WHERE source = 'music';
DELETE FROM ops.schema_migrations WHERE filename = '157_listening_events.up.sql';

COMMIT;
