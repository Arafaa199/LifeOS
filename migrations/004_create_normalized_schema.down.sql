-- Migration: 004_create_normalized_schema (ROLLBACK)
-- Purpose: Remove normalized.* schema
--
-- WARNING: This will delete all normalized data. Raw data is preserved.

BEGIN;

-- Drop triggers first
DROP TRIGGER IF EXISTS set_updated_at_daily_recovery ON normalized.daily_recovery;
DROP TRIGGER IF EXISTS set_updated_at_daily_sleep ON normalized.daily_sleep;
DROP TRIGGER IF EXISTS set_updated_at_daily_strain ON normalized.daily_strain;
DROP TRIGGER IF EXISTS set_updated_at_body_metrics ON normalized.body_metrics;
DROP TRIGGER IF EXISTS set_updated_at_transactions ON normalized.transactions;
DROP TRIGGER IF EXISTS set_updated_at_food_log ON normalized.food_log;
DROP TRIGGER IF EXISTS set_updated_at_water_log ON normalized.water_log;
DROP TRIGGER IF EXISTS set_updated_at_mood_log ON normalized.mood_log;

-- Drop helper function
DROP FUNCTION IF EXISTS normalized.update_updated_at();

-- Drop tables (in order due to no FK dependencies between them)
DROP TABLE IF EXISTS normalized.mood_log;
DROP TABLE IF EXISTS normalized.water_log;
DROP TABLE IF EXISTS normalized.food_log;
DROP TABLE IF EXISTS normalized.transactions;
DROP TABLE IF EXISTS normalized.body_metrics;
DROP TABLE IF EXISTS normalized.daily_strain;
DROP TABLE IF EXISTS normalized.daily_sleep;
DROP TABLE IF EXISTS normalized.daily_recovery;

-- Drop schema
DROP SCHEMA IF EXISTS normalized;

COMMIT;
