-- Migration 015 Rollback: Drop raw_events table

BEGIN;

DROP TABLE IF EXISTS finance.raw_events CASCADE;

COMMIT;
