-- Migration 142 DOWN: Remove coalescing queue and triggers

BEGIN;

-- Drop triggers from all tables
DROP TRIGGER IF EXISTS trg_queue_refresh_recovery ON health.whoop_recovery;
DROP TRIGGER IF EXISTS trg_process_refresh_recovery ON health.whoop_recovery;
DROP TRIGGER IF EXISTS trg_queue_refresh_sleep ON health.whoop_sleep;
DROP TRIGGER IF EXISTS trg_process_refresh_sleep ON health.whoop_sleep;
DROP TRIGGER IF EXISTS trg_queue_refresh_strain ON health.whoop_strain;
DROP TRIGGER IF EXISTS trg_process_refresh_strain ON health.whoop_strain;
DROP TRIGGER IF EXISTS trg_queue_refresh_metrics ON health.metrics;
DROP TRIGGER IF EXISTS trg_process_refresh_metrics ON health.metrics;
DROP TRIGGER IF EXISTS trg_queue_refresh_transactions ON finance.transactions;
DROP TRIGGER IF EXISTS trg_process_refresh_transactions ON finance.transactions;

-- Drop functions
DROP FUNCTION IF EXISTS life.process_refresh_queue();
DROP FUNCTION IF EXISTS life.queue_refresh_on_write();

-- Drop queue table
DROP TABLE IF EXISTS life.refresh_queue;

-- Restore migration 141's synchronous trigger (optional)
-- CREATE TRIGGER trg_refresh_facts_on_recovery
--     AFTER INSERT OR UPDATE ON health.whoop_recovery
--     FOR EACH ROW EXECUTE FUNCTION life.trigger_refresh_on_write();

COMMIT;
