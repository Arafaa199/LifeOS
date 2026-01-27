-- Migration: 086_feed_status_triggers
-- Converts life.feed_status from a slow full-table-scan VIEW into a
-- lightweight lookup TABLE auto-updated by INSERT triggers on source tables.
--
-- Problem: life.feed_status scans entire source tables on every query,
--          only tracks 4 sources, and queries legacy tables instead of raw.*.
-- Fix:     Create life.feed_status_live TABLE with per-source last_event_at,
--          add AFTER INSERT triggers on all source tables to keep it current,
--          and replace the VIEW with one that reads from the lookup table.

BEGIN;

-- ============================================================================
-- 0. Drop existing VIEW (column type changes require DROP + CREATE)
-- ============================================================================
DROP VIEW IF EXISTS life.feed_status;

-- ============================================================================
-- 1. Create the lookup table
-- ============================================================================
CREATE TABLE IF NOT EXISTS life.feed_status_live (
    source       TEXT PRIMARY KEY,
    last_event_at TIMESTAMPTZ,
    events_today  INTEGER DEFAULT 0,
    last_updated  TIMESTAMPTZ DEFAULT NOW()
);

-- Seed with all known sources
INSERT INTO life.feed_status_live (source, last_event_at, events_today) VALUES
    ('whoop',       (SELECT MAX(created_at) FROM health.whoop_recovery),
                    (SELECT COUNT(*) FROM health.whoop_recovery WHERE date = CURRENT_DATE)),
    ('healthkit',   (SELECT MAX(ingested_at) FROM raw.healthkit_samples),
                    (SELECT COUNT(*) FROM raw.healthkit_samples WHERE start_date::date = CURRENT_DATE)),
    ('bank_sms',    (SELECT MAX(created_at) FROM finance.transactions WHERE source = 'sms'),
                    (SELECT COUNT(*) FROM finance.transactions WHERE source = 'sms' AND date = CURRENT_DATE)),
    ('manual',      (SELECT MAX(created_at) FROM nutrition.food_log),
                    (SELECT COUNT(*) FROM nutrition.food_log WHERE date = CURRENT_DATE)),
    ('github',      (SELECT MAX(ingested_at) FROM raw.github_events),
                    (SELECT COUNT(*) FROM raw.github_events WHERE created_at_github::date = CURRENT_DATE)),
    ('behavioral',  (SELECT MAX(created_at) FROM life.behavioral_events),
                    (SELECT COUNT(*) FROM life.behavioral_events WHERE created_at::date = CURRENT_DATE)),
    ('location',    (SELECT MAX(created_at) FROM life.locations),
                    (SELECT COUNT(*) FROM life.locations WHERE created_at::date = CURRENT_DATE)),
    ('receipts',    (SELECT MAX(created_at) FROM finance.receipts),
                    (SELECT COUNT(*) FROM finance.receipts WHERE created_at::date = CURRENT_DATE))
ON CONFLICT (source) DO UPDATE SET
    last_event_at = EXCLUDED.last_event_at,
    events_today = EXCLUDED.events_today,
    last_updated = NOW();

-- ============================================================================
-- 2. Create the trigger function
-- ============================================================================
CREATE OR REPLACE FUNCTION life.update_feed_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO life.feed_status_live (source, last_event_at, events_today, last_updated)
    VALUES (TG_ARGV[0], NOW(), 1, NOW())
    ON CONFLICT (source) DO UPDATE SET
        last_event_at = NOW(),
        events_today = CASE
            WHEN life.feed_status_live.last_updated::date < CURRENT_DATE THEN 1
            ELSE life.feed_status_live.events_today + 1
        END,
        last_updated = NOW();
    RETURN NEW;
END;
$$;

-- ============================================================================
-- 3. Attach triggers to all source tables
-- ============================================================================

-- WHOOP (legacy tables — n8n writes here, triggers propagate to raw.*)
CREATE OR REPLACE TRIGGER trg_feed_whoop
    AFTER INSERT ON health.whoop_recovery
    FOR EACH ROW EXECUTE FUNCTION life.update_feed_status('whoop');

-- HealthKit samples
CREATE OR REPLACE TRIGGER trg_feed_healthkit
    AFTER INSERT ON raw.healthkit_samples
    FOR EACH ROW EXECUTE FUNCTION life.update_feed_status('healthkit');

-- Finance transactions (SMS + manual + receipts all land here)
CREATE OR REPLACE TRIGGER trg_feed_bank_sms
    AFTER INSERT ON finance.transactions
    FOR EACH ROW EXECUTE FUNCTION life.update_feed_status('bank_sms');

-- Nutrition food log
CREATE OR REPLACE TRIGGER trg_feed_manual
    AFTER INSERT ON nutrition.food_log
    FOR EACH ROW EXECUTE FUNCTION life.update_feed_status('manual');

-- GitHub events
CREATE OR REPLACE TRIGGER trg_feed_github
    AFTER INSERT ON raw.github_events
    FOR EACH ROW EXECUTE FUNCTION life.update_feed_status('github');

-- Behavioral events
CREATE OR REPLACE TRIGGER trg_feed_behavioral
    AFTER INSERT ON life.behavioral_events
    FOR EACH ROW EXECUTE FUNCTION life.update_feed_status('behavioral');

-- Location events
CREATE OR REPLACE TRIGGER trg_feed_location
    AFTER INSERT ON life.locations
    FOR EACH ROW EXECUTE FUNCTION life.update_feed_status('location');

-- Receipts
CREATE OR REPLACE TRIGGER trg_feed_receipts
    AFTER INSERT ON finance.receipts
    FOR EACH ROW EXECUTE FUNCTION life.update_feed_status('receipts');

-- ============================================================================
-- 4. Replace the VIEW to read from the lookup table
-- ============================================================================
CREATE OR REPLACE VIEW life.feed_status AS
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
FROM life.feed_status_live;

-- ============================================================================
-- 5. Helper: reset events_today at midnight (call from cron or daily refresh)
-- ============================================================================
CREATE OR REPLACE FUNCTION life.reset_feed_events_today()
RETURNS void
LANGUAGE sql
AS $$
    UPDATE life.feed_status_live
    SET events_today = 0, last_updated = NOW()
    WHERE last_updated::date < CURRENT_DATE;
$$;

COMMIT;
