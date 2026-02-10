-- No-op: rolling back would revert to migration 188's version (without work_minutes),
-- which is the broken state we're fixing. Use migration 188 down if needed.
SELECT 1;
