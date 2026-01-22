-- Rollback: 004_dashboard_read_model
-- Removes dashboard read model (baselines + views)

BEGIN;

-- Drop functions first (they depend on tables)
DROP FUNCTION IF EXISTS life.refresh_all(INT);
DROP FUNCTION IF EXISTS life.refresh_baselines();
DROP FUNCTION IF EXISTS life.refresh_daily_facts(DATE);

-- Drop views
DROP VIEW IF EXISTS ops.feed_status;
DROP VIEW IF EXISTS dashboard.v_recent_events;
DROP VIEW IF EXISTS dashboard.v_trends;
DROP VIEW IF EXISTS dashboard.v_today;

-- Drop materialized view
DROP MATERIALIZED VIEW IF EXISTS life.baselines;

-- Drop table
DROP TABLE IF EXISTS life.daily_facts;

-- Drop schemas (only if empty)
DROP SCHEMA IF EXISTS ops;
DROP SCHEMA IF EXISTS dashboard;
DROP SCHEMA IF EXISTS life;

COMMIT;
