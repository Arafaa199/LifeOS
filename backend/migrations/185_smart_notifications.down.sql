BEGIN;

DROP TABLE IF EXISTS core.notification_log;

DELETE FROM ops.schema_migrations WHERE filename = '185_smart_notifications.up.sql';

COMMIT;
