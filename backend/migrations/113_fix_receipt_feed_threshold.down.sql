-- Revert migration 113: Restore 8-hour receipt threshold
UPDATE life.feed_status_live
SET expected_interval = INTERVAL '8 hours'
WHERE source = 'receipts';
