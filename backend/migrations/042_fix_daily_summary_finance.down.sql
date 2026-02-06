-- Rollback: 042_fix_daily_summary_finance
-- Note: This migration updates life.get_daily_summary() to use canonical finance layer.
-- Rollback would require restoring the previous function version which is not available.
-- The function signature is unchanged, only implementation details.

-- No-op: Function evolution - previous version not preserved
SELECT 'Migration 042 cannot be rolled back - function was iteratively improved';
