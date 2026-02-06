-- Rollback: 093_domains_status_and_freshness_fix
-- Drops ops.v_domains_status view (get_payload function not reverted - superseded by 094)

DROP VIEW IF EXISTS ops.v_domains_status;

-- Note: get_payload() not reverted - migration 094 supersedes this version
SELECT 'Migration 093 partially rolled back - view dropped, function not reverted';
