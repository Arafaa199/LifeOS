-- Migration 171: Idempotency Keys + Transaction Safety
--
-- Problem: OfflineQueue retries re-POST the same payload. Without server-side
-- idempotency, retried food logs / water logs / expenses create duplicates.
--
-- Solution:
--   (a) Add client_id to normalized tables that receive iOS writes
--   (b) Add UNIQUE constraint on client_id (NULL allowed for legacy rows)
--   (c) Wrap critical PL/pgSQL functions in BEGIN/EXCEPTION blocks
--   (d) Add safe upsert helpers for n8n webhook handlers

BEGIN;

-- =============================================================================
-- 1. ADD client_id TO NORMALIZED TABLES
-- =============================================================================

-- Food log: iOS sends food entries with offline retry
ALTER TABLE normalized.food_log
ADD COLUMN IF NOT EXISTS client_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uix_food_log_client_id
    ON normalized.food_log (client_id)
    WHERE client_id IS NOT NULL;

COMMENT ON COLUMN normalized.food_log.client_id IS 'Client-generated UUID for idempotent retries from OfflineQueue';

-- Water log: iOS sends water entries with offline retry
ALTER TABLE normalized.water_log
ADD COLUMN IF NOT EXISTS client_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uix_water_log_client_id
    ON normalized.water_log (client_id)
    WHERE client_id IS NOT NULL;

-- Mood log: iOS sends mood entries with offline retry
ALTER TABLE normalized.mood_log
ADD COLUMN IF NOT EXISTS client_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uix_mood_log_client_id
    ON normalized.mood_log (client_id)
    WHERE client_id IS NOT NULL;

-- Transactions: iOS sends expenses with offline retry
ALTER TABLE normalized.transactions
ADD COLUMN IF NOT EXISTS client_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uix_transactions_client_id
    ON normalized.transactions (client_id)
    WHERE client_id IS NOT NULL;

-- =============================================================================
-- 2. SAFE UPSERT HELPER (for n8n webhook handlers)
--
-- n8n code nodes call this to INSERT OR skip if client_id exists.
-- Returns the row id (existing or new) + whether it was a duplicate.
-- =============================================================================

CREATE OR REPLACE FUNCTION normalized.safe_insert_food_log(
    p_date DATE,
    p_meal_time TEXT DEFAULT NULL,
    p_food_name TEXT DEFAULT NULL,
    p_calories INT DEFAULT NULL,
    p_protein_g NUMERIC DEFAULT NULL,
    p_carbs_g NUMERIC DEFAULT NULL,
    p_fat_g NUMERIC DEFAULT NULL,
    p_fiber_g NUMERIC DEFAULT NULL,
    p_source TEXT DEFAULT 'ios_app',
    p_client_id TEXT DEFAULT NULL,
    p_raw_id BIGINT DEFAULT NULL,
    p_food_id INT DEFAULT NULL
)
RETURNS TABLE(row_id INT, was_duplicate BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
    existing_id INT;
BEGIN
    -- Check client_id idempotency first
    IF p_client_id IS NOT NULL THEN
        SELECT id INTO existing_id
        FROM normalized.food_log
        WHERE client_id = p_client_id;

        IF existing_id IS NOT NULL THEN
            RETURN QUERY SELECT existing_id, TRUE;
            RETURN;
        END IF;
    END IF;

    -- Insert new row
    INSERT INTO normalized.food_log (
        date, meal_time, food_name, calories, protein_g, carbs_g, fat_g,
        fiber_g, source, client_id, raw_id, food_id, logged_at
    ) VALUES (
        p_date, p_meal_time, p_food_name, p_calories, p_protein_g, p_carbs_g,
        p_fat_g, p_fiber_g, p_source, p_client_id, p_raw_id, p_food_id, NOW()
    )
    RETURNING id INTO existing_id;

    RETURN QUERY SELECT existing_id, FALSE;

EXCEPTION WHEN unique_violation THEN
    -- Race condition: another request inserted same client_id between check and insert
    SELECT id INTO existing_id
    FROM normalized.food_log
    WHERE client_id = p_client_id;
    RETURN QUERY SELECT COALESCE(existing_id, 0), TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION normalized.safe_insert_water_log(
    p_date DATE,
    p_amount_ml INT,
    p_source TEXT DEFAULT 'ios_app',
    p_client_id TEXT DEFAULT NULL,
    p_raw_id BIGINT DEFAULT NULL
)
RETURNS TABLE(row_id INT, was_duplicate BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
    existing_id INT;
BEGIN
    IF p_client_id IS NOT NULL THEN
        SELECT id INTO existing_id
        FROM normalized.water_log
        WHERE client_id = p_client_id;

        IF existing_id IS NOT NULL THEN
            RETURN QUERY SELECT existing_id, TRUE;
            RETURN;
        END IF;
    END IF;

    INSERT INTO normalized.water_log (date, amount_ml, source, client_id, raw_id, logged_at)
    VALUES (p_date, p_amount_ml, p_source, p_client_id, p_raw_id, NOW())
    RETURNING id INTO existing_id;

    RETURN QUERY SELECT existing_id, FALSE;

EXCEPTION WHEN unique_violation THEN
    SELECT id INTO existing_id
    FROM normalized.water_log
    WHERE client_id = p_client_id;
    RETURN QUERY SELECT COALESCE(existing_id, 0), TRUE;
END;
$$;

-- =============================================================================
-- 3. TRANSACTION-SAFE WRAPPER FOR core.update_daily_summary
-- =============================================================================

CREATE OR REPLACE FUNCTION core.update_daily_summary_safe(target_date DATE)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM core.update_daily_summary(target_date);
    RETURN TRUE;
EXCEPTION WHEN OTHERS THEN
    -- Log to DLQ instead of silently failing
    PERFORM ops.enqueue_dead_letter(
        'pipeline',
        'update_daily_summary',
        SQLERRM,
        SQLSTATE,
        NULL,
        jsonb_build_object('target_date', target_date)
    );
    RAISE WARNING 'update_daily_summary failed for %: %', target_date, SQLERRM;
    RETURN FALSE;
END;
$$;

-- =============================================================================
-- 4. TRANSACTION-SAFE WRAPPER FOR nutrition.recalculate_meal_macros
-- =============================================================================

CREATE OR REPLACE FUNCTION nutrition.recalculate_meal_macros_safe(p_meal_id INT)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM nutrition.recalculate_meal_macros(p_meal_id);
    RETURN TRUE;
EXCEPTION WHEN OTHERS THEN
    PERFORM ops.enqueue_dead_letter(
        'pipeline',
        'recalculate_meal_macros',
        SQLERRM,
        SQLSTATE,
        NULL,
        jsonb_build_object('meal_id', p_meal_id)
    );
    RAISE WARNING 'recalculate_meal_macros failed for meal %: %', p_meal_id, SQLERRM;
    RETURN FALSE;
END;
$$;

COMMIT;
