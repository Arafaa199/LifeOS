-- Rollback migration 095: Remove per-source thresholds

BEGIN;

-- Drop and recreate original VIEW with hardcoded 1h/24h thresholds
DROP VIEW IF EXISTS life.feed_status;
CREATE VIEW life.feed_status AS
SELECT
  source,
  last_event_at,
  events_today,
  CASE
    WHEN last_event_at IS NULL THEN 'error'
    WHEN last_event_at >= (now() - INTERVAL '1 hour') THEN 'ok'
    WHEN last_event_at >= (now() - INTERVAL '24 hours') THEN 'stale'
    ELSE 'error'
  END AS status
FROM life.feed_status_live;

-- Remove the column
ALTER TABLE life.feed_status_live DROP COLUMN IF EXISTS expected_interval;

COMMIT;
