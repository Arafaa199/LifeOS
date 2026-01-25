-- Migration: 077_health_timeseries (DOWN)
-- Removes health time series view and function

BEGIN;

DROP FUNCTION IF EXISTS facts.get_health_timeseries(INT);
DROP VIEW IF EXISTS facts.v_daily_health_timeseries;

COMMIT;
