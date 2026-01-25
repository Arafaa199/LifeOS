-- Migration 072: Meal Inference Engine
-- Creates SQL-based meal inference from behavioral signals
-- No manual input required

-- Table for user feedback on inferred meals
CREATE TABLE IF NOT EXISTS life.meal_confirmations (
    id SERIAL PRIMARY KEY,
    inferred_meal_date DATE NOT NULL,
    inferred_meal_time TIME NOT NULL,
    meal_type TEXT NOT NULL CHECK (meal_type IN ('breakfast', 'lunch', 'dinner', 'snack')),
    confidence NUMERIC(3,2) NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
    user_action TEXT NOT NULL CHECK (user_action IN ('confirmed', 'skipped')),
    signals_used JSONB NOT NULL,
    confirmed_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (inferred_meal_date, inferred_meal_time)
);

CREATE INDEX IF NOT EXISTS idx_meal_confirmations_date ON life.meal_confirmations(inferred_meal_date);
CREATE INDEX IF NOT EXISTS idx_meal_confirmations_user_action ON life.meal_confirmations(user_action);

-- View: Inferred meals from behavioral signals
CREATE OR REPLACE VIEW life.v_inferred_meals AS
WITH
-- Restaurant transactions → high confidence meals
restaurant_meals AS (
    SELECT
        (transaction_at AT TIME ZONE 'Asia/Dubai')::DATE as meal_date,
        (transaction_at AT TIME ZONE 'Asia/Dubai')::TIME as meal_time,
        CASE
            WHEN EXTRACT(HOUR FROM transaction_at AT TIME ZONE 'Asia/Dubai') BETWEEN 6 AND 10 THEN 'breakfast'
            WHEN EXTRACT(HOUR FROM transaction_at AT TIME ZONE 'Asia/Dubai') BETWEEN 11 AND 15 THEN 'lunch'
            WHEN EXTRACT(HOUR FROM transaction_at AT TIME ZONE 'Asia/Dubai') BETWEEN 18 AND 22 THEN 'dinner'
            ELSE 'snack'
        END as meal_type,
        0.9 as confidence,
        'restaurant' as source,
        jsonb_build_object(
            'source', 'restaurant_transaction',
            'merchant', merchant_name,
            'amount', amount,
            'currency', currency
        ) as signals_used
    FROM finance.transactions
    WHERE category = 'Restaurant'
        AND amount < 0  -- Only expenses
        AND (transaction_at AT TIME ZONE 'Asia/Dubai')::DATE >= CURRENT_DATE - INTERVAL '30 days'
),
-- Home cooking signals → medium confidence
home_cooking AS (
    SELECT DISTINCT
        dls.day as meal_date,
        '12:30:00'::TIME as meal_time,  -- Default lunch time
        'lunch' as meal_type,
        0.6 as confidence,
        'home_cooking' as source,
        jsonb_build_object(
            'source', 'home_location',
            'hours_at_home', dls.hours_at_home,
            'tv_hours', COALESCE(dbs.tv_hours, 0),
            'tv_off', COALESCE(dbs.tv_hours, 0) < 0.5
        ) as signals_used
    FROM life.daily_location_summary dls
    LEFT JOIN life.daily_behavioral_summary dbs ON dbs.day = dls.day
    WHERE dls.day >= CURRENT_DATE - INTERVAL '30 days'
        AND dls.hours_at_home >= 0.5  -- At home for at least 30 min during day
        -- TV off or low usage
        AND COALESCE(dbs.tv_hours, 0) < 1.0
        -- Has location data for that day
        AND dls.hours_at_home IS NOT NULL
),
-- Dinner at home (evening presence)
home_dinner AS (
    SELECT DISTINCT
        dls.day as meal_date,
        '19:30:00'::TIME as meal_time,  -- Default dinner time
        'dinner' as meal_type,
        0.6 as confidence,
        'home_cooking' as source,
        jsonb_build_object(
            'source', 'home_location_evening',
            'hours_at_home', dls.hours_at_home,
            'last_arrival', dls.last_arrival
        ) as signals_used
    FROM life.daily_location_summary dls
    WHERE dls.day >= CURRENT_DATE - INTERVAL '30 days'
        AND dls.hours_at_home >= 1.0  -- At home for at least 1 hour
        -- Last arrival was in evening
        AND dls.last_arrival IS NOT NULL
        AND EXTRACT(HOUR FROM dls.last_arrival AT TIME ZONE 'Asia/Dubai') BETWEEN 17 AND 22
),
-- Grocery purchase → low confidence (cooked later)
grocery_inference AS (
    SELECT DISTINCT
        t.transaction_at::DATE as meal_date,
        '20:00:00'::TIME as meal_time,  -- Evening meal
        'dinner' as meal_type,
        0.4 as confidence,
        'grocery_purchase' as source,
        jsonb_build_object(
            'source', 'grocery_transaction',
            'merchant', t.merchant_name,
            'amount', t.amount,
            'home_evening', EXISTS (
                SELECT 1 FROM life.daily_location_summary dls
                WHERE dls.day = t.transaction_at::DATE
                    AND dls.hours_at_home > 0
                    AND dls.last_arrival IS NOT NULL
                    AND EXTRACT(HOUR FROM dls.last_arrival AT TIME ZONE 'Asia/Dubai') BETWEEN 18 AND 22
            )
        ) as signals_used
    FROM finance.transactions t
    WHERE t.category = 'Grocery'
        AND t.amount < 0  -- Only expenses
        AND t.transaction_at::DATE >= CURRENT_DATE - INTERVAL '30 days'
        -- Only if home that evening
        AND EXISTS (
            SELECT 1 FROM life.daily_location_summary dls
            WHERE dls.day = t.transaction_at::DATE
                AND dls.hours_at_home > 0
        )
)
-- Combine all meal inferences
SELECT
    inferred.meal_date as inferred_at_date,
    inferred.meal_time as inferred_at_time,
    inferred.meal_type,
    inferred.confidence,
    inferred.source as inference_source,
    inferred.signals_used,
    -- Check if already confirmed/skipped
    COALESCE(mc.user_action, 'pending') as confirmation_status
FROM (
    SELECT * FROM restaurant_meals
    UNION ALL
    SELECT * FROM home_cooking
    UNION ALL
    SELECT * FROM home_dinner
    UNION ALL
    SELECT * FROM grocery_inference
) inferred
LEFT JOIN life.meal_confirmations mc
    ON mc.inferred_meal_date = inferred.meal_date
    AND mc.inferred_meal_time = inferred.meal_time
-- Only show unconfirmed meals
WHERE COALESCE(mc.user_action, 'pending') = 'pending'
ORDER BY inferred.meal_date DESC, inferred.meal_time DESC;

-- Function: Get pending meal confirmations for a date
CREATE OR REPLACE FUNCTION life.get_pending_meal_confirmations(target_date DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
    meal_date DATE,
    meal_time TIME,
    meal_type TEXT,
    confidence NUMERIC,
    inference_source TEXT,
    signals_used JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        v.inferred_at_date,
        v.inferred_at_time,
        v.meal_type,
        v.confidence,
        v.inference_source,
        v.signals_used
    FROM life.v_inferred_meals v
    WHERE v.inferred_at_date = target_date
        AND v.confirmation_status = 'pending'
    ORDER BY v.inferred_at_time DESC;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON TABLE life.meal_confirmations IS 'User feedback on inferred meals (confirmed/skipped)';
COMMENT ON VIEW life.v_inferred_meals IS 'Inferred meal times from restaurant TX, home cooking signals, grocery purchases';
COMMENT ON FUNCTION life.get_pending_meal_confirmations IS 'Returns unconfirmed meal inferences for a specific date';
