-- Migration: 005_create_facts_schema (ROLLBACK)
-- Purpose: Remove facts.* schema and all related objects

BEGIN;

-- Drop functions first (they depend on tables)
DROP FUNCTION IF EXISTS facts.rebuild_all();
DROP FUNCTION IF EXISTS facts.refresh_date_range(DATE, DATE);
DROP FUNCTION IF EXISTS facts.refresh_daily_summary(DATE);
DROP FUNCTION IF EXISTS facts.refresh_daily_finance(DATE);
DROP FUNCTION IF EXISTS facts.refresh_daily_nutrition(DATE);
DROP FUNCTION IF EXISTS facts.refresh_daily_health(DATE);

-- Drop tables
DROP TABLE IF EXISTS facts.daily_summary;
DROP TABLE IF EXISTS facts.daily_finance;
DROP TABLE IF EXISTS facts.daily_nutrition;
DROP TABLE IF EXISTS facts.daily_health;

-- Drop schema
DROP SCHEMA IF EXISTS facts;

COMMIT;
