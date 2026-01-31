-- Migration 104 down: Restore GitHub feed to 24h threshold
UPDATE life.feed_status_live
SET expected_interval = '24:00:00'::interval
WHERE source = 'github';
