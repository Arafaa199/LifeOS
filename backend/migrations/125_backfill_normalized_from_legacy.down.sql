-- Migration 125 DOWN: No destructive rollback needed
-- This migration only re-synced data from legacy → normalized.
-- Rolling back would mean reverting to stale data, which is not useful.
-- To truly "undo", you'd need to restore from the pre-migration backup.
SELECT 'Migration 125 down: No action needed (data-only backfill)' AS notice;
