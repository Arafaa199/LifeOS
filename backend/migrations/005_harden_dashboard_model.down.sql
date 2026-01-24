-- Rollback: 005_harden_dashboard_model
-- Reverts to simpler versions without locking/logging

BEGIN;

-- Drop versioned function
DROP FUNCTION IF EXISTS dashboard.get_payload(DATE);

-- Restore simpler views (will be recreated by 004)
DROP VIEW IF EXISTS dashboard.v_trends;
DROP VIEW IF EXISTS dashboard.v_today;

-- Drop hardened functions
DROP FUNCTION IF EXISTS life.refresh_all(INT, VARCHAR);
DROP FUNCTION IF EXISTS life.refresh_baselines(VARCHAR);
DROP FUNCTION IF EXISTS life.refresh_daily_facts(DATE, VARCHAR);

-- Drop helper functions
DROP FUNCTION IF EXISTS life.to_dubai_date(TIMESTAMPTZ);
DROP FUNCTION IF EXISTS life.dubai_today();

-- Drop refresh log (preserve data by not dropping)
-- DROP TABLE IF EXISTS ops.refresh_log;

COMMIT;
