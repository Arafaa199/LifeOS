-- Migration 141 DOWN: Remove event-driven refresh trigger

BEGIN;

DROP TRIGGER IF EXISTS trg_refresh_facts_on_recovery ON health.whoop_recovery;

-- Keep the function for potential future use, or drop if you want clean removal:
-- DROP FUNCTION IF EXISTS life.trigger_refresh_on_write();

COMMIT;
