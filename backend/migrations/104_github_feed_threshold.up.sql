-- Migration 104: Adjust GitHub feed expected_interval to 7 days
-- Reason: GitHub sync workflow runs every 6h when active, but is currently
-- inactive in n8n. Even when active, GitHub activity is sporadic (gaps of
-- 1-3 days between active days). The 24h threshold causes permanent "error"
-- status. 7 days matches real-world sync frequency.

UPDATE life.feed_status_live
SET expected_interval = '7 days'::interval
WHERE source = 'github';
