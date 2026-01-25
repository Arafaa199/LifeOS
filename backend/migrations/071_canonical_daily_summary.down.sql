-- Rollback migration 071: Canonical Daily Summary Materialized View

-- Drop functions
DROP FUNCTION IF EXISTS life.get_daily_summary_canonical(DATE);
DROP FUNCTION IF EXISTS life.refresh_daily_summary(DATE);

-- Drop materialized view
DROP MATERIALIZED VIEW IF EXISTS life.mv_daily_summary;
