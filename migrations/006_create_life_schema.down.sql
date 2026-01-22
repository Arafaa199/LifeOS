-- Rollback: 006_enhance_life_schema
-- Removes added columns and feed_status view

-- Drop the view
DROP VIEW IF EXISTS life.feed_status;

-- Remove added columns (preserves original table structure)
ALTER TABLE life.daily_facts DROP COLUMN IF EXISTS spending_by_category;
ALTER TABLE life.daily_facts DROP COLUMN IF EXISTS weight_delta_7d;
ALTER TABLE life.daily_facts DROP COLUMN IF EXISTS weight_delta_30d;
ALTER TABLE life.daily_facts DROP COLUMN IF EXISTS sleep_hours;
ALTER TABLE life.daily_facts DROP COLUMN IF EXISTS deep_sleep_hours;

-- Note: The original refresh_daily_facts function should be restored manually
-- if needed. The enhanced version is backwards compatible.
