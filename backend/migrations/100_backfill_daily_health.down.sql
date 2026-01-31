-- Down migration 100: No structural changes to revert
-- The up migration only backfills/refreshes data rows and removes empty placeholders.
-- To revert: re-run life.refresh_all() which will re-populate from current source data.
-- No-op migration — data-only changes are idempotent.
SELECT 'Migration 100 down: no-op (data backfill only)' AS info;
