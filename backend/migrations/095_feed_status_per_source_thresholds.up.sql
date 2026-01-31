-- Migration 095: Per-source thresholds for feed_status
-- Fixes false alarms where event-driven and low-frequency feeds show "error"
-- by replacing uniform 1h/24h thresholds with per-source expected intervals.

BEGIN;

-- Add expected_interval column
ALTER TABLE life.feed_status_live
  ADD COLUMN IF NOT EXISTS expected_interval INTERVAL NOT NULL DEFAULT INTERVAL '1 hour';

-- Set per-source thresholds based on actual update frequency
UPDATE life.feed_status_live SET expected_interval = CASE source
  -- WHOOP: polls every 15 min via HA
  WHEN 'whoop'        THEN INTERVAL '1 hour'
  WHEN 'whoop_sleep'  THEN INTERVAL '1 hour'
  WHEN 'whoop_strain' THEN INTERVAL '1 hour'
  -- HealthKit: syncs when user opens app (daily-ish)
  WHEN 'healthkit'    THEN INTERVAL '48 hours'
  -- Weight: Eufy scale → HealthKit → app (every few days)
  WHEN 'weight'       THEN INTERVAL '48 hours'
  -- Bank SMS: event-driven, multiple per day usually
  WHEN 'bank_sms'     THEN INTERVAL '48 hours'
  -- GitHub: syncs every 6h via n8n cron
  WHEN 'github'       THEN INTERVAL '24 hours'
  -- Receipts: every 6h via n8n cron
  WHEN 'receipts'     THEN INTERVAL '8 hours'
  -- Manual entries: user-driven, infrequent
  WHEN 'manual'       THEN INTERVAL '7 days'
  -- Behavioral: HA automations (motion, TV) — event-driven
  WHEN 'behavioral'   THEN INTERVAL '7 days'
  -- Location: HA automations (arrive/depart) — event-driven
  WHEN 'location'     THEN INTERVAL '7 days'
  ELSE INTERVAL '24 hours'
END;

-- Drop and recreate the VIEW to use per-source thresholds
-- (Cannot use CREATE OR REPLACE because column list changes)
-- ok: within 1x interval, stale: within 3x interval, error: beyond 3x
DROP VIEW IF EXISTS life.feed_status;
CREATE VIEW life.feed_status AS
SELECT
  source,
  last_event_at,
  events_today,
  expected_interval,
  CASE
    WHEN last_event_at IS NULL THEN 'unknown'
    WHEN last_event_at >= (now() - expected_interval) THEN 'ok'
    WHEN last_event_at >= (now() - expected_interval * 3) THEN 'stale'
    ELSE 'error'
  END AS status
FROM life.feed_status_live;

COMMIT;
