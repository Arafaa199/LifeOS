-- Rollback: 094_reliability_fixes
-- Drops ops.trigger_errors table and related objects

-- Drop trigger
DROP TRIGGER IF EXISTS trg_feed_healthkit_metrics ON health.metrics;

-- Drop function
DROP FUNCTION IF EXISTS life.refresh_all(INTEGER, TEXT);

-- Drop table
DROP TABLE IF EXISTS ops.trigger_errors;

-- Note: Propagation functions and get_payload() not reverted - would need previous versions
SELECT 'Migration 094 partially rolled back - table and trigger dropped, functions not reverted';
