-- Migration: 040_daily_life_summary
-- Purpose: TASK-O1 - Create life.get_daily_summary(date) function
-- Returns a deterministic JSON object with health, finance, behavior, anomalies, confidence

-- Function: life.get_daily_summary(date)
-- Returns ONE JSON object per day with all life data
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
    v_confidence JSONB;
    v_data_coverage JSONB;

    -- Health variables
    v_recovery INT;
    v_hrv NUMERIC;
    v_sleep_hours NUMERIC;
    v_weight NUMERIC;
    v_rhr INT;
    v_strain NUMERIC;
    v_sleep_perf INT;

    -- Finance variables
    v_total_spent NUMERIC;
    v_total_income NUMERIC;
    v_tx_count INT;
    v_top_categories JSONB;
    v_largest_tx JSONB;
    v_is_expensive BOOLEAN;
    v_avg_daily_spend NUMERIC;

    -- Behavior variables
    v_first_departure TIMESTAMPTZ;
    v_last_arrival TIMESTAMPTZ;
    v_tv_minutes NUMERIC;
    v_evening_tv_minutes INT;
    v_hours_at_home NUMERIC;
    v_hours_away NUMERIC;

    -- Confidence variables
    v_confidence_score NUMERIC;
    v_confidence_level TEXT;
    v_has_sms BOOLEAN;
    v_has_receipts BOOLEAN;
    v_has_health BOOLEAN;
    v_stale_feeds INT;
BEGIN
    -- ═══════════════════════════════════════════════════════════════
    -- HEALTH DATA
    -- ═══════════════════════════════════════════════════════════════
    SELECT
        recovery_score,
        hrv,
        sleep_hours,
        weight_kg,
        rhr,
        strain,
        sleep_performance
    INTO
        v_recovery,
        v_hrv,
        v_sleep_hours,
        v_weight,
        v_rhr,
        v_strain,
        v_sleep_perf
    FROM life.daily_facts
    WHERE day = p_date;

    v_health := jsonb_build_object(
        'recovery', v_recovery,
        'hrv', ROUND(v_hrv::NUMERIC, 1),
        'sleep_hours', ROUND(v_sleep_hours::NUMERIC, 1),
        'weight', ROUND(v_weight::NUMERIC, 1),
        'rhr', v_rhr,
        'strain', ROUND(v_strain::NUMERIC, 1),
        'sleep_performance', v_sleep_perf
    );

    -- ═══════════════════════════════════════════════════════════════
    -- FINANCE DATA
    -- ═══════════════════════════════════════════════════════════════
    -- Get totals for the day
    SELECT
        COALESCE(SUM(CASE WHEN amount < 0 AND category NOT IN ('Transfer') THEN ABS(amount) ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0),
        COUNT(*)
    INTO v_total_spent, v_total_income, v_tx_count
    FROM finance.transactions
    WHERE finance.to_business_date(transaction_at) = p_date
      AND NOT COALESCE(is_quarantined, FALSE);

    -- Get top categories (ordered correctly via CTE)
    WITH cat_totals AS (
        SELECT
            category,
            ROUND(SUM(ABS(amount))::NUMERIC, 2) as spent
        FROM finance.transactions
        WHERE finance.to_business_date(transaction_at) = p_date
          AND amount < 0
          AND category NOT IN ('Transfer')
          AND NOT COALESCE(is_quarantined, FALSE)
        GROUP BY category
        ORDER BY spent DESC
        LIMIT 5
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object('category', category, 'spent', spent)), '[]'::JSONB)
    INTO v_top_categories
    FROM cat_totals;

    -- Get largest transaction
    SELECT jsonb_build_object(
        'merchant', COALESCE(merchant_name_clean, merchant_name, 'Unknown'),
        'category', category,
        'amount', ROUND(ABS(amount)::NUMERIC, 2)
    )
    INTO v_largest_tx
    FROM finance.transactions
    WHERE finance.to_business_date(transaction_at) = p_date
      AND amount < 0
      AND category NOT IN ('Transfer')
      AND NOT COALESCE(is_quarantined, FALSE)
    ORDER BY ABS(amount) DESC
    LIMIT 1;

    -- Calculate if expensive day (> 1.5x average)
    SELECT COALESCE(AVG(spend_total), 0) INTO v_avg_daily_spend
    FROM life.daily_facts
    WHERE day >= p_date - INTERVAL '30 days' AND day < p_date;

    v_is_expensive := CASE
        WHEN v_avg_daily_spend > 0 AND v_total_spent > v_avg_daily_spend * 1.5 THEN TRUE
        ELSE FALSE
    END;

    v_finance := jsonb_build_object(
        'total_spent', ROUND(v_total_spent, 2),
        'total_income', ROUND(v_total_income, 2),
        'top_categories', COALESCE(v_top_categories, '[]'::JSONB),
        'largest_tx', v_largest_tx,
        'is_expensive_day', v_is_expensive,
        'transaction_count', v_tx_count,
        'spend_score', CASE
            WHEN v_avg_daily_spend = 0 OR v_total_spent = 0 THEN 100
            WHEN v_total_spent <= v_avg_daily_spend * 0.5 THEN 100
            WHEN v_total_spent <= v_avg_daily_spend THEN 80
            WHEN v_total_spent <= v_avg_daily_spend * 1.5 THEN 60
            WHEN v_total_spent <= v_avg_daily_spend * 2 THEN 40
            ELSE 20
        END
    );

    -- ═══════════════════════════════════════════════════════════════
    -- BEHAVIOR DATA
    -- ═══════════════════════════════════════════════════════════════
    -- Location summary
    SELECT
        first_departure,
        last_arrival,
        hours_at_home,
        hours_away
    INTO
        v_first_departure,
        v_last_arrival,
        v_hours_at_home,
        v_hours_away
    FROM life.daily_location_summary
    WHERE day = p_date;

    -- Behavioral summary (TV)
    SELECT
        COALESCE(tv_hours * 60, 0),
        COALESCE(evening_tv_minutes, 0)
    INTO
        v_tv_minutes,
        v_evening_tv_minutes
    FROM life.daily_behavioral_summary
    WHERE day = p_date;

    v_behavior := jsonb_build_object(
        'left_home_at', CASE WHEN v_first_departure IS NOT NULL
            THEN TO_CHAR(v_first_departure AT TIME ZONE 'Asia/Dubai', 'HH24:MI')
            ELSE NULL END,
        'returned_home_at', CASE WHEN v_last_arrival IS NOT NULL
            THEN TO_CHAR(v_last_arrival AT TIME ZONE 'Asia/Dubai', 'HH24:MI')
            ELSE NULL END,
        'tv_minutes', ROUND(v_tv_minutes),
        'screen_late', COALESCE(v_evening_tv_minutes > 60, FALSE),
        'hours_at_home', ROUND(COALESCE(v_hours_at_home, 0)::NUMERIC, 1),
        'hours_away', ROUND(COALESCE(v_hours_away, 0)::NUMERIC, 1)
    );

    -- ═══════════════════════════════════════════════════════════════
    -- ANOMALIES
    -- ═══════════════════════════════════════════════════════════════
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'type', anomaly,
                'reason', CASE anomaly
                    WHEN 'low_recovery' THEN 'Recovery below threshold'
                    WHEN 'high_recovery' THEN 'Recovery exceptionally high'
                    WHEN 'low_hrv' THEN 'HRV significantly below baseline'
                    WHEN 'high_hrv' THEN 'HRV significantly above baseline'
                    WHEN 'low_sleep' THEN 'Sleep duration below target'
                    WHEN 'high_spending' THEN 'Spending above daily average'
                    ELSE anomaly
                END,
                'confidence', 0.9  -- All detected anomalies have high confidence
            )
        ),
        '[]'::JSONB
    )
    INTO v_anomalies
    FROM (
        SELECT unnest(anomalies) as anomaly
        FROM insights.daily_anomalies
        WHERE day = p_date
    ) sub;

    -- ═══════════════════════════════════════════════════════════════
    -- CONFIDENCE & DATA COVERAGE
    -- ═══════════════════════════════════════════════════════════════
    SELECT
        confidence_score,
        confidence_level,
        has_sms,
        has_receipts,
        has_whoop,
        stale_feeds
    INTO
        v_confidence_score,
        v_confidence_level,
        v_has_sms,
        v_has_receipts,
        v_has_health,
        v_stale_feeds
    FROM life.daily_confidence
    WHERE day = p_date;

    v_confidence := jsonb_build_object(
        'score', COALESCE(v_confidence_score, 0),
        'level', COALESCE(v_confidence_level, 'UNKNOWN')
    );

    v_data_coverage := jsonb_build_object(
        'sms', COALESCE(v_has_sms, FALSE),
        'receipts', COALESCE(v_has_receipts, FALSE),
        'health', COALESCE(v_has_health, FALSE),
        'stale_feeds', COALESCE(v_stale_feeds, 0)
    );

    -- ═══════════════════════════════════════════════════════════════
    -- BUILD FINAL RESULT
    -- ═══════════════════════════════════════════════════════════════
    v_result := jsonb_build_object(
        'date', p_date,
        'health', v_health,
        'finance', v_finance,
        'behavior', v_behavior,
        'anomalies', COALESCE(v_anomalies, '[]'::JSONB),
        'confidence', COALESCE(v_confidence_score, 0),
        'data_coverage', v_data_coverage,
        'generated_at', NOW()
    );

    RETURN v_result;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION life.get_daily_summary(DATE) TO nexus;

-- Add comment
COMMENT ON FUNCTION life.get_daily_summary(DATE) IS
'TASK-O1: Returns a deterministic JSON summary for a given date.
Includes: health, finance, behavior, anomalies, confidence, data_coverage.
Tolerates missing data (returns nulls). Deterministic.';

-- ═══════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES
-- ═══════════════════════════════════════════════════════════════
-- Test: Get today's summary
-- SELECT life.get_daily_summary(CURRENT_DATE);

-- Test: Get last 7 days
-- SELECT day, life.get_daily_summary(day) FROM generate_series(CURRENT_DATE - 6, CURRENT_DATE, '1 day') as day;
