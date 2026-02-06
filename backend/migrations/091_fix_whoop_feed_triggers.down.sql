-- Rollback: 091_fix_whoop_feed_triggers
-- Drops the corrected triggers (but does not restore broken 090 functions)

DROP TRIGGER IF EXISTS trg_feed_whoop_sleep ON health.whoop_sleep;
DROP TRIGGER IF EXISTS trg_feed_whoop_strain ON health.whoop_strain;

-- Note: Broken functions from 090 are not restored (they were non-functional)
SELECT 'Migration 091 rolled back - triggers dropped';
