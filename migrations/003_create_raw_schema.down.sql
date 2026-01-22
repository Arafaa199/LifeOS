-- Rollback: 003_create_raw_schema
-- Purpose: Remove raw.* schema and all tables
-- WARNING: This will delete all raw data. Only use during development or if data is backed up.

BEGIN;

-- Drop triggers first
DROP TRIGGER IF EXISTS prevent_update_whoop_cycles ON raw.whoop_cycles;
DROP TRIGGER IF EXISTS prevent_update_whoop_sleep ON raw.whoop_sleep;
DROP TRIGGER IF EXISTS prevent_update_whoop_strain ON raw.whoop_strain;
DROP TRIGGER IF EXISTS prevent_update_healthkit_samples ON raw.healthkit_samples;
DROP TRIGGER IF EXISTS prevent_update_bank_sms ON raw.bank_sms;
DROP TRIGGER IF EXISTS prevent_update_manual_entries ON raw.manual_entries;

-- Drop the trigger function
DROP FUNCTION IF EXISTS raw.prevent_modification();

-- Drop all tables in reverse order
DROP TABLE IF EXISTS raw.manual_entries;
DROP TABLE IF EXISTS raw.bank_sms;
DROP TABLE IF EXISTS raw.healthkit_samples;
DROP TABLE IF EXISTS raw.whoop_strain;
DROP TABLE IF EXISTS raw.whoop_sleep;
DROP TABLE IF EXISTS raw.whoop_cycles;

-- Drop the schema (only if empty)
DROP SCHEMA IF EXISTS raw;

COMMIT;
