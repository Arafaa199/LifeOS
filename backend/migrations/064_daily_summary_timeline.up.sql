-- Migration: Add finance timeline to life.get_daily_summary()
-- Task: TASK-VIS.2
-- Date: 2026-01-25

-- Drop existing function
DROP FUNCTION IF EXISTS life.get_daily_summary(DATE);

-- Recreate with timeline support
CREATE OR REPLACE FUNCTION life.get_daily_summary(p_date DATE DEFAULT CURRENT_DATE)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSONB;
    v_health JSONB;
    v_finance JSONB;
    v_behavior JSONB;
    v_anomalies JSONB;
    v_confidence NUMERIC;
    v_data_coverage JSONB;
    v_timeline JSONB;
BEGIN
    -- Health section (unchanged)
    SELECT jsonb_build_object(
        'recovery', recovery_score,
        'hrv', hrv,
        'rhr', rhr,
        'sleep_hours', ROUND((sleep_minutes / 60.0)::NUMERIC, 2),
        'sleep_performance', sleep_performance,
        'strain', strain,
        'weight', weight_kg
    ) INTO v_health
    FROM life.daily_facts
    WHERE day = p_date;

    -- Finance timeline (NEW)
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'time', time,
                'type', event_type,
                'amount', amount,
                'currency', currency,
                'merchant', merchant,
                'category', category,
                'source', source,
                'actionable', is_actionable
            ) ORDER BY event_time DESC
        ),
        '[]'::jsonb
    ) INTO v_timeline
    FROM finance.v_timeline
    WHERE date = p_date;

    -- Finance section (enhanced with timeline)
    SELECT jsonb_build_object(
        'total_spent', COALESCE(SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END), 0),
        'total_income', COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0),
        'transaction_count', COUNT(*),
        'top_categories', (
            SELECT COALESCE(jsonb_agg(
                jsonb_build_object('category', category, 'spent', spent)
                ORDER BY spent DESC
            ), '[]'::jsonb)
            FROM (
                SELECT category, SUM(ABS(amount)) as spent
                FROM finance.transactions
                WHERE DATE(transaction_at AT TIME ZONE 'Asia/Dubai') = p_date
                  AND amount < 0
                  AND category != 'Transfer'
                GROUP BY category
                ORDER BY spent DESC
                LIMIT 5
            ) t
        ),
        'largest_tx', (
            SELECT jsonb_build_object(
                'merchant', merchant_name,
                'amount', ABS(amount),
                'category', category
            )
            FROM finance.transactions
            WHERE DATE(transaction_at AT TIME ZONE 'Asia/Dubai') = p_date
              AND amount < 0
            ORDER BY ABS(amount) DESC
            LIMIT 1
        ),
        'is_expensive_day', (
            SELECT COALESCE(SUM(ABS(amount)), 0) > 500
            FROM finance.transactions
            WHERE DATE(transaction_at AT TIME ZONE 'Asia/Dubai') = p_date
              AND amount < 0
        ),
        'spend_score', COALESCE((
            SELECT 100 - LEAST(100, (SUM(ABS(amount)) / 10)::INT)
            FROM finance.transactions
            WHERE DATE(transaction_at AT TIME ZONE 'Asia/Dubai') = p_date
              AND amount < 0
        ), 100),
        'timeline', v_timeline
    ) INTO v_finance
    FROM finance.transactions
    WHERE DATE(transaction_at AT TIME ZONE 'Asia/Dubai') = p_date;

    -- Behavior section (unchanged)
    SELECT jsonb_build_object(
        'hours_at_home', COALESCE(loc.hours_at_home, 0),
        'hours_away', COALESCE(loc.hours_away, 0),
        'left_home_at', loc.first_departure,
        'returned_home_at', loc.last_arrival,
        'tv_minutes', beh.tv_hours * 60,
        'screen_late', COALESCE(beh.tv_hours > 0, false)
    ) INTO v_behavior
    FROM life.daily_location_summary loc
    LEFT JOIN life.daily_behavioral_summary beh ON loc.day = beh.day
    WHERE loc.day = p_date;

    -- Anomalies (unchanged)
    SELECT COALESCE(anomalies_explained, '[]'::jsonb) INTO v_anomalies
    FROM insights.daily_anomalies_explained
    WHERE day = p_date;

    -- Confidence (unchanged)
    SELECT COALESCE(confidence_score, 1.0) INTO v_confidence
    FROM life.daily_confidence
    WHERE day = p_date;

    -- Data coverage (unchanged)
    SELECT jsonb_build_object(
        'sms', has_sms,
        'receipts', has_receipts,
        'health', has_whoop,
        'stale_feeds', stale_feeds
    ) INTO v_data_coverage
    FROM life.daily_confidence
    WHERE day = p_date;

    -- Build result
    v_result := jsonb_build_object(
        'date', p_date,
        'health', COALESCE(v_health, '{}'::jsonb),
        'finance', COALESCE(v_finance, '{}'::jsonb),
        'behavior', COALESCE(v_behavior, '{}'::jsonb),
        'anomalies', COALESCE(v_anomalies, '[]'::jsonb),
        'confidence', COALESCE(v_confidence, 1.0),
        'data_coverage', COALESCE(v_data_coverage, '{}'::jsonb),
        'generated_at', NOW()
    );

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION life.get_daily_summary(DATE) IS 'Returns complete daily summary including finance timeline (TASK-VIS.2)';
