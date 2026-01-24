-- TASK-O3: Explanation Layer for Anomalies
-- Adds dynamic explanations to anomalies with actual metric values

-- Create new view with explanations
DROP VIEW IF EXISTS insights.daily_anomalies_explained CASCADE;

CREATE VIEW insights.daily_anomalies_explained AS
WITH baselines AS (
    SELECT
        AVG(spend_total) AS avg_spend,
        STDDEV(spend_total) AS std_spend,
        AVG(recovery_score) AS avg_recovery,
        STDDEV(recovery_score) AS std_recovery,
        AVG(sleep_hours) AS avg_sleep,
        STDDEV(sleep_hours) AS std_sleep,
        AVG(hrv) AS avg_hrv,
        STDDEV(hrv) AS std_hrv
    FROM life.daily_facts
    WHERE day >= (NOW() - INTERVAL '30 days') AND day < (NOW() - INTERVAL '1 day')
),
daily_z_scores AS (
    SELECT
        lf.day,
        lf.spend_total,
        lf.recovery_score,
        lf.sleep_hours,
        lf.hrv,
        b.avg_spend,
        b.avg_recovery,
        b.avg_sleep,
        b.avg_hrv,
        CASE WHEN b.std_spend > 0
            THEN (lf.spend_total - b.avg_spend) / b.std_spend
            ELSE 0
        END AS spend_z_score,
        CASE WHEN b.std_recovery > 0
            THEN (lf.recovery_score::NUMERIC - b.avg_recovery) / b.std_recovery
            ELSE 0
        END AS recovery_z_score,
        CASE WHEN b.std_sleep > 0
            THEN (lf.sleep_hours - b.avg_sleep) / b.std_sleep
            ELSE 0
        END AS sleep_z_score,
        CASE WHEN b.std_hrv > 0
            THEN (lf.hrv - b.avg_hrv) / b.std_hrv
            ELSE 0
        END AS hrv_z_score
    FROM life.daily_facts lf
    CROSS JOIN baselines b
    WHERE lf.day >= (NOW() - INTERVAL '7 days')
),
anomaly_details AS (
    SELECT
        day,
        spend_total,
        recovery_score,
        sleep_hours,
        hrv,
        avg_spend,
        avg_recovery,
        avg_sleep,
        avg_hrv,
        ROUND(spend_z_score, 2) AS spend_z_score,
        ROUND(recovery_z_score, 2) AS recovery_z_score,
        ROUND(sleep_z_score, 2) AS sleep_z_score,
        ROUND(hrv_z_score, 2) AS hrv_z_score,
        -- Anomaly detection
        CASE
            WHEN ABS(spend_z_score) > 2 THEN
                CASE WHEN spend_z_score > 0 THEN 'high_spend' ELSE 'low_spend' END
        END AS spend_anomaly,
        CASE
            WHEN ABS(recovery_z_score) > 2 THEN
                CASE WHEN recovery_z_score > 0 THEN 'high_recovery' ELSE 'low_recovery' END
        END AS recovery_anomaly,
        CASE
            WHEN ABS(sleep_z_score) > 2 THEN
                CASE WHEN sleep_z_score > 0 THEN 'high_sleep' ELSE 'low_sleep' END
        END AS sleep_anomaly,
        CASE
            WHEN ABS(hrv_z_score) > 2 THEN
                CASE WHEN hrv_z_score > 0 THEN 'high_hrv' ELSE 'low_hrv' END
        END AS hrv_anomaly
    FROM daily_z_scores
)
SELECT
    day,
    spend_total,
    recovery_score,
    sleep_hours,
    hrv,
    spend_z_score,
    recovery_z_score,
    sleep_z_score,
    hrv_z_score,
    -- Aggregated anomalies array (backward compatible)
    array_remove(ARRAY[spend_anomaly, recovery_anomaly, sleep_anomaly, hrv_anomaly], NULL) AS anomalies,
    -- JSON array with full details for each anomaly
    (
        SELECT COALESCE(jsonb_agg(anomaly_obj ORDER BY confidence DESC), '[]'::JSONB)
        FROM (
            -- High Spend anomaly
            SELECT jsonb_build_object(
                'type', 'high_spend',
                'reason', 'Spending significantly above baseline',
                'explanation', 'Spent ' || ROUND(spend_total::NUMERIC, 2) || ' AED, which is ' ||
                    ROUND(ABS(spend_z_score)::NUMERIC, 1) || ' standard deviations above your 30-day average of ' ||
                    ROUND(avg_spend::NUMERIC, 2) || ' AED (' ||
                    ROUND((spend_total / NULLIF(avg_spend, 0) * 100 - 100)::NUMERIC, 0) || '% higher).',
                'confidence', 0.95,
                'metrics', jsonb_build_object(
                    'value', ROUND(spend_total::NUMERIC, 2),
                    'baseline', ROUND(avg_spend::NUMERIC, 2),
                    'z_score', spend_z_score,
                    'unit', 'AED'
                )
            ) AS anomaly_obj, 0.95 AS confidence
            WHERE spend_anomaly = 'high_spend'

            UNION ALL

            -- Low Spend anomaly
            SELECT jsonb_build_object(
                'type', 'low_spend',
                'reason', 'Spending significantly below baseline',
                'explanation', 'Spent only ' || ROUND(spend_total::NUMERIC, 2) || ' AED, which is ' ||
                    ROUND(ABS(spend_z_score)::NUMERIC, 1) || ' standard deviations below your 30-day average of ' ||
                    ROUND(avg_spend::NUMERIC, 2) || ' AED (' ||
                    ROUND((100 - spend_total / NULLIF(avg_spend, 0) * 100)::NUMERIC, 0) || '% lower).',
                'confidence', 0.85,
                'metrics', jsonb_build_object(
                    'value', ROUND(spend_total::NUMERIC, 2),
                    'baseline', ROUND(avg_spend::NUMERIC, 2),
                    'z_score', spend_z_score,
                    'unit', 'AED'
                )
            ), 0.85
            WHERE spend_anomaly = 'low_spend'

            UNION ALL

            -- Low Recovery anomaly
            SELECT jsonb_build_object(
                'type', 'low_recovery',
                'reason', 'Recovery score significantly below baseline',
                'explanation', 'Recovery at ' || recovery_score || '%, which is ' ||
                    ROUND(ABS(recovery_z_score)::NUMERIC, 1) || ' standard deviations below your 30-day average of ' ||
                    ROUND(avg_recovery::NUMERIC, 0) || '% (' ||
                    ROUND((avg_recovery - recovery_score)::NUMERIC, 0) || ' points lower). Consider prioritizing rest.',
                'confidence', 0.9,
                'metrics', jsonb_build_object(
                    'value', recovery_score,
                    'baseline', ROUND(avg_recovery::NUMERIC, 0),
                    'z_score', recovery_z_score,
                    'unit', '%'
                )
            ), 0.9
            WHERE recovery_anomaly = 'low_recovery'

            UNION ALL

            -- High Recovery anomaly
            SELECT jsonb_build_object(
                'type', 'high_recovery',
                'reason', 'Recovery score significantly above baseline',
                'explanation', 'Recovery at ' || recovery_score || '%, which is ' ||
                    ROUND(ABS(recovery_z_score)::NUMERIC, 1) || ' standard deviations above your 30-day average of ' ||
                    ROUND(avg_recovery::NUMERIC, 0) || '% (' ||
                    ROUND((recovery_score - avg_recovery)::NUMERIC, 0) || ' points higher). Great day for demanding activities.',
                'confidence', 0.9,
                'metrics', jsonb_build_object(
                    'value', recovery_score,
                    'baseline', ROUND(avg_recovery::NUMERIC, 0),
                    'z_score', recovery_z_score,
                    'unit', '%'
                )
            ), 0.9
            WHERE recovery_anomaly = 'high_recovery'

            UNION ALL

            -- Low HRV anomaly
            SELECT jsonb_build_object(
                'type', 'low_hrv',
                'reason', 'HRV significantly below baseline',
                'explanation', 'HRV at ' || ROUND(hrv::NUMERIC, 1) || ' ms, which is ' ||
                    ROUND(ABS(hrv_z_score)::NUMERIC, 1) || ' standard deviations below your 30-day average of ' ||
                    ROUND(avg_hrv::NUMERIC, 1) || ' ms (' ||
                    ROUND((avg_hrv - hrv)::NUMERIC, 1) || ' ms lower). May indicate stress or fatigue.',
                'confidence', 0.9,
                'metrics', jsonb_build_object(
                    'value', ROUND(hrv::NUMERIC, 1),
                    'baseline', ROUND(avg_hrv::NUMERIC, 1),
                    'z_score', hrv_z_score,
                    'unit', 'ms'
                )
            ), 0.9
            WHERE hrv_anomaly = 'low_hrv'

            UNION ALL

            -- High HRV anomaly
            SELECT jsonb_build_object(
                'type', 'high_hrv',
                'reason', 'HRV significantly above baseline',
                'explanation', 'HRV at ' || ROUND(hrv::NUMERIC, 1) || ' ms, which is ' ||
                    ROUND(ABS(hrv_z_score)::NUMERIC, 1) || ' standard deviations above your 30-day average of ' ||
                    ROUND(avg_hrv::NUMERIC, 1) || ' ms (' ||
                    ROUND((hrv - avg_hrv)::NUMERIC, 1) || ' ms higher). Indicates good recovery.',
                'confidence', 0.9,
                'metrics', jsonb_build_object(
                    'value', ROUND(hrv::NUMERIC, 1),
                    'baseline', ROUND(avg_hrv::NUMERIC, 1),
                    'z_score', hrv_z_score,
                    'unit', 'ms'
                )
            ), 0.9
            WHERE hrv_anomaly = 'high_hrv'

            UNION ALL

            -- Low Sleep anomaly
            SELECT jsonb_build_object(
                'type', 'low_sleep',
                'reason', 'Sleep duration significantly below baseline',
                'explanation', 'Slept ' || ROUND(sleep_hours::NUMERIC, 1) || ' hours, which is ' ||
                    ROUND(ABS(sleep_z_score)::NUMERIC, 1) || ' standard deviations below your 30-day average of ' ||
                    ROUND(avg_sleep::NUMERIC, 1) || ' hours (' ||
                    ROUND((avg_sleep - sleep_hours) * 60::NUMERIC, 0) || ' minutes less).',
                'confidence', 0.85,
                'metrics', jsonb_build_object(
                    'value', ROUND(sleep_hours::NUMERIC, 1),
                    'baseline', ROUND(avg_sleep::NUMERIC, 1),
                    'z_score', sleep_z_score,
                    'unit', 'hours'
                )
            ), 0.85
            WHERE sleep_anomaly = 'low_sleep'

            UNION ALL

            -- High Sleep anomaly
            SELECT jsonb_build_object(
                'type', 'high_sleep',
                'reason', 'Sleep duration significantly above baseline',
                'explanation', 'Slept ' || ROUND(sleep_hours::NUMERIC, 1) || ' hours, which is ' ||
                    ROUND(ABS(sleep_z_score)::NUMERIC, 1) || ' standard deviations above your 30-day average of ' ||
                    ROUND(avg_sleep::NUMERIC, 1) || ' hours (' ||
                    ROUND((sleep_hours - avg_sleep) * 60::NUMERIC, 0) || ' minutes more).',
                'confidence', 0.85,
                'metrics', jsonb_build_object(
                    'value', ROUND(sleep_hours::NUMERIC, 1),
                    'baseline', ROUND(avg_sleep::NUMERIC, 1),
                    'z_score', sleep_z_score,
                    'unit', 'hours'
                )
            ), 0.85
            WHERE sleep_anomaly = 'high_sleep'
        ) sub
    ) AS anomalies_explained
FROM anomaly_details
ORDER BY day DESC;

COMMENT ON VIEW insights.daily_anomalies_explained IS 'Daily anomalies with full explanations including actual metrics and baselines';


-- Update life.get_daily_summary() to use the new view with explanations
CREATE OR REPLACE FUNCTION life.get_daily_summary(p_date DATE DEFAULT CURRENT_DATE)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $function$
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

    -- FINANCE DATA
    SELECT
        COALESCE(SUM(CASE WHEN amount < 0 AND category NOT IN ('Transfer') THEN ABS(amount) ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0),
        COUNT(*)
    INTO v_total_spent, v_total_income, v_tx_count
    FROM finance.transactions
    WHERE finance.to_business_date(transaction_at) = p_date
      AND NOT COALESCE(is_quarantined, FALSE);

    -- Get top categories (ordered correctly)
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

    -- ANOMALIES (now with full explanations from new view)
    SELECT COALESCE(anomalies_explained, '[]'::JSONB)
    INTO v_anomalies
    FROM insights.daily_anomalies_explained
    WHERE day = p_date;

    -- If no row in view, return empty array
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
$function$;

COMMENT ON FUNCTION life.get_daily_summary(DATE) IS 'Returns complete daily life summary with anomaly explanations';
