-- Rollback: 160_fix_weight_source_priority
-- This would revert to the old logic (latest recorded_at wins)
-- Not recommended - the new logic is strictly better

-- Note: To truly rollback, you'd need to restore the previous function version
-- For safety, this is a no-op since the fix is beneficial
SELECT 'Migration 160 rollback is a no-op - weight source priority is beneficial';
