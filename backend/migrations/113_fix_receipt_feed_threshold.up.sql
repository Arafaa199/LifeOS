-- Migration 113: Fix receipt feed status threshold
-- Receipts come from grocery shopping (every 2-5 days), not every 8 hours.
-- 8h threshold caused permanent "error" status. 7 days matches actual cadence.

UPDATE life.feed_status_live
SET expected_interval = INTERVAL '7 days'
WHERE source = 'receipts';
