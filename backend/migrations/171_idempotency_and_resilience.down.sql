-- Migration 171 Down: Remove idempotency columns and safe wrappers

BEGIN;

DROP FUNCTION IF EXISTS nutrition.recalculate_meal_macros_safe(INT);
DROP FUNCTION IF EXISTS core.update_daily_summary_safe(DATE);
DROP FUNCTION IF EXISTS normalized.safe_insert_water_log(DATE, INT, TEXT, TEXT, BIGINT);
DROP FUNCTION IF EXISTS normalized.safe_insert_food_log(DATE, TEXT, TEXT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TEXT, BIGINT, INT);

DROP INDEX IF EXISTS normalized.uix_transactions_client_id;
DROP INDEX IF EXISTS normalized.uix_mood_log_client_id;
DROP INDEX IF EXISTS normalized.uix_water_log_client_id;
DROP INDEX IF EXISTS normalized.uix_food_log_client_id;

ALTER TABLE normalized.transactions DROP COLUMN IF EXISTS client_id;
ALTER TABLE normalized.mood_log DROP COLUMN IF EXISTS client_id;
ALTER TABLE normalized.water_log DROP COLUMN IF EXISTS client_id;
ALTER TABLE normalized.food_log DROP COLUMN IF EXISTS client_id;

COMMIT;
