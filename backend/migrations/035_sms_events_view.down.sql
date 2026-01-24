-- Rollback M6.3 sms_events view
DROP VIEW IF EXISTS raw.sms_events_summary;
DROP VIEW IF EXISTS raw.sms_events;
DROP TYPE IF EXISTS raw.sms_intent;
