-- Rollback: 086_feed_status_triggers
BEGIN;

-- Remove triggers
DROP TRIGGER IF EXISTS trg_feed_whoop ON health.whoop_recovery;
DROP TRIGGER IF EXISTS trg_feed_healthkit ON raw.healthkit_samples;
DROP TRIGGER IF EXISTS trg_feed_bank_sms ON finance.transactions;
DROP TRIGGER IF EXISTS trg_feed_manual ON nutrition.food_log;
DROP TRIGGER IF EXISTS trg_feed_github ON raw.github_events;
DROP TRIGGER IF EXISTS trg_feed_behavioral ON life.behavioral_events;
DROP TRIGGER IF EXISTS trg_feed_location ON life.locations;
DROP TRIGGER IF EXISTS trg_feed_receipts ON finance.receipts;

-- Remove functions
DROP FUNCTION IF EXISTS life.update_feed_status();
DROP FUNCTION IF EXISTS life.reset_feed_events_today();

-- Drop the lookup table
DROP TABLE IF EXISTS life.feed_status_live;

-- Restore original VIEW (from migration 006)
CREATE OR REPLACE VIEW life.feed_status AS
WITH sources AS (
    SELECT
        'whoop' AS source,
        MAX(created_at) AS last_event_at,
        COUNT(*) FILTER (WHERE date = CURRENT_DATE) AS events_today
    FROM health.whoop_recovery
    UNION ALL
    SELECT
        'healthkit' AS source,
        MAX(created_at) AS last_event_at,
        COUNT(*) FILTER (WHERE date = CURRENT_DATE) AS events_today
    FROM health.metrics
    WHERE source = 'healthkit'
    UNION ALL
    SELECT
        'bank_sms' AS source,
        MAX(created_at) AS last_event_at,
        COUNT(*) FILTER (WHERE date = CURRENT_DATE) AS events_today
    FROM finance.transactions
    UNION ALL
    SELECT
        'manual' AS source,
        MAX(created_at) AS last_event_at,
        COUNT(*) FILTER (WHERE date = CURRENT_DATE) AS events_today
    FROM nutrition.food_log
)
SELECT
    source,
    last_event_at,
    events_today,
    CASE
        WHEN last_event_at IS NULL THEN 'error'
        WHEN last_event_at >= NOW() - INTERVAL '1 hour' THEN 'ok'
        WHEN last_event_at >= NOW() - INTERVAL '24 hours' THEN 'stale'
        ELSE 'error'
    END AS status
FROM sources;

COMMIT;
