-- Migration: 042_fix_daily_summary_finance.up.sql
-- Purpose: Update life.get_daily_summary() to use canonical finance layer
-- Date: 2026-01-24
--
-- FIXES:
-- Uses finance.daily_totals_aed and finance.canonical_transactions
-- instead of querying raw transactions with buggy transaction_at

CREATE OR REPLACE FUNCTION life.get_daily_summary(p_date DATE DEFAULT CURRENT_DATE)
RETURNS JSONB AS $$
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

    -- Finance variables (now from canonical layer)
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
    -- HEALTH DATA
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

    -- FINANCE DATA (using canonical layer)
    SELECT
        COALESCE(expense_aed, 0),
        COALESCE(income_aed, 0),
        COALESCE(transaction_count, 0)
    INTO v_total_spent, v_total_income, v_tx_count
    FROM finance.daily_totals_aed
    WHERE day = p_date;

    -- If no row found, set defaults
    IF v_total_spent IS NULL THEN
        v_total_spent := 0;
        v_total_income := 0;
        v_tx_count := 0;
    END IF;

    -- Get top categories (from canonical transactions, using actual date)
    WITH cat_totals AS (
        SELECT
            category,
            ROUND(SUM(canonical_amount)::NUMERIC, 2) as spent
        FROM finance.canonical_transactions
        WHERE transaction_date = p_date
          AND direction = 'expense'
          AND is_base_currency
          AND NOT exclude_from_totals
        GROUP BY category
        ORDER BY spent DESC
        LIMIT 5
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object('category', category, 'spent', spent)), '[]'::JSONB)
    INTO v_top_categories
    FROM cat_totals;

    -- Get largest transaction (from canonical transactions)
    SELECT jsonb_build_object(
        'merchant', COALESCE(merchant, 'Unknown'),
        'category', category,
        'amount', ROUND(canonical_amount::NUMERIC, 2)
    )
    INTO v_largest_tx
    FROM finance.canonical_transactions
    WHERE transaction_date = p_date
      AND direction = 'expense'
      AND is_base_currency
      AND NOT exclude_from_totals
    ORDER BY canonical_amount DESC
    LIMIT 1;

    -- Calculate if expensive day (> 1.5x average of last 30 days)
    SELECT COALESCE(AVG(expense_aed), 0) INTO v_avg_daily_spend
    FROM finance.daily_totals_aed
    WHERE day >= p_date - INTERVAL '30 days' AND day < p_date
      AND expense_aed > 0;

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

    -- BEHAVIOR DATA
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

    -- ANOMALIES
    SELECT COALESCE(anomalies_explained, '[]'::JSONB)
    INTO v_anomalies
    FROM insights.daily_anomalies_explained
    WHERE day = p_date;

    v_anomalies := COALESCE(v_anomalies, '[]'::JSONB);

    -- CONFIDENCE & DATA COVERAGE
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

    -- BUILD FINAL RESULT
    v_result := jsonb_build_object(
        'date', p_date,
        'health', v_health,
        'finance', v_finance,
        'behavior', v_behavior,
        'anomalies', v_anomalies,
        'confidence', COALESCE(v_confidence_score, 0),
        'data_coverage', v_data_coverage,
        'generated_at', NOW()
    );

    RETURN v_result;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION life.get_daily_summary IS
'Returns complete daily life summary as JSON.
Uses canonical finance layer (finance.daily_totals_aed) for accurate spend calculations.
Fixed in migration 042 to use actual transaction dates instead of buggy transaction_at.';
