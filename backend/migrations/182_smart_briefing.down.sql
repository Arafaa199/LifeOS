BEGIN;

-- Rollback: restore original life.explain_today() v1

CREATE OR REPLACE FUNCTION life.explain_today(target_date date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    the_day DATE;
    facts RECORD;
    result JSONB;
    health_parts TEXT[] := '{}';
    finance_parts TEXT[] := '{}';
    nutrition_parts TEXT[] := '{}';
    activity_parts TEXT[] := '{}';
    data_gaps TEXT[] := '{}';
    briefing_parts TEXT[] := '{}';
    assertions JSONB;
    dubai_check BOOLEAN;
    freshness_check BOOLEAN;
    completeness_check BOOLEAN;
    recovery_label TEXT;
    sleep_label TEXT;
    spend_label TEXT;
BEGIN
    the_day := COALESCE(target_date, life.dubai_today());

    -- ASSERTIONS
    dubai_check := life.assert_dubai_day(the_day);
    SELECT * INTO facts FROM life.daily_facts WHERE day = the_day;

    IF facts.computed_at IS NOT NULL THEN
        freshness_check := (NOW() - facts.computed_at) < INTERVAL '6 hours';
    ELSE
        freshness_check := FALSE;
    END IF;

    completeness_check := COALESCE(facts.data_completeness, 0) >= 0.30;

    assertions := jsonb_build_object(
        'dubai_day_valid', dubai_check,
        'data_fresh', freshness_check,
        'data_sufficient', completeness_check,
        'all_passed', dubai_check AND freshness_check AND completeness_check,
        'checked_at', NOW(),
        'target_date', the_day,
        'computed_at', facts.computed_at,
        'data_completeness', facts.data_completeness
    );

    IF facts.day IS NULL THEN
        RETURN jsonb_build_object(
            'target_date', the_day,
            'has_data', FALSE,
            'briefing', 'No data recorded for ' || to_char(the_day, 'FMMonth DD'),
            'data_gaps', ARRAY['No daily_facts row exists for this date'],
            'assertions', assertions
        );
    END IF;

    -- HEALTH SUMMARY
    IF facts.recovery_score IS NOT NULL THEN
        IF facts.recovery_score >= 67 THEN
            recovery_label := 'high';
            health_parts := array_append(health_parts,
                'Recovery is high (' || facts.recovery_score || '%) — good capacity for strain');
            briefing_parts := array_append(briefing_parts,
                'High recovery (' || facts.recovery_score || '%)');
        ELSIF facts.recovery_score >= 34 THEN
            recovery_label := 'moderate';
            health_parts := array_append(health_parts,
                'Recovery is moderate (' || facts.recovery_score || '%) — balanced day ahead');
            briefing_parts := array_append(briefing_parts,
                'Moderate recovery (' || facts.recovery_score || '%)');
        ELSE
            recovery_label := 'low';
            health_parts := array_append(health_parts,
                'Recovery is low (' || facts.recovery_score || '%) — prioritize rest');
            briefing_parts := array_append(briefing_parts,
                'Low recovery (' || facts.recovery_score || '%)');
        END IF;
    ELSE
        data_gaps := array_append(data_gaps, 'Recovery score not available');
    END IF;

    IF facts.hrv IS NOT NULL THEN
        health_parts := array_append(health_parts, 'HRV at ' || ROUND(facts.hrv, 0) || 'ms');
    END IF;

    IF facts.sleep_hours IS NOT NULL THEN
        IF facts.sleep_hours >= 7 THEN
            sleep_label := 'good';
            health_parts := array_append(health_parts,
                'Got ' || ROUND(facts.sleep_hours, 1) || 'h sleep (good)');
            briefing_parts := array_append(briefing_parts,
                ROUND(facts.sleep_hours, 1) || 'h sleep');
        ELSIF facts.sleep_hours >= 6 THEN
            sleep_label := 'fair';
            health_parts := array_append(health_parts,
                'Got ' || ROUND(facts.sleep_hours, 1) || 'h sleep (fair)');
            briefing_parts := array_append(briefing_parts,
                ROUND(facts.sleep_hours, 1) || 'h sleep');
        ELSE
            sleep_label := 'poor';
            health_parts := array_append(health_parts,
                'Only ' || ROUND(facts.sleep_hours, 1) || 'h sleep (poor)');
            briefing_parts := array_append(briefing_parts,
                'only ' || ROUND(facts.sleep_hours, 1) || 'h sleep');
        END IF;

        IF facts.deep_sleep_hours IS NOT NULL AND facts.deep_sleep_hours > 0 THEN
            health_parts := array_append(health_parts,
                ROUND(facts.deep_sleep_hours, 1) || 'h deep sleep');
        END IF;
    ELSE
        data_gaps := array_append(data_gaps, 'Sleep data not available');
    END IF;

    IF facts.strain IS NOT NULL THEN
        IF facts.strain >= 14 THEN
            health_parts := array_append(health_parts,
                'Strain was high (' || ROUND(facts.strain, 1) || ')');
        ELSIF facts.strain >= 10 THEN
            health_parts := array_append(health_parts,
                'Moderate strain (' || ROUND(facts.strain, 1) || ')');
        ELSE
            health_parts := array_append(health_parts,
                'Low strain (' || ROUND(facts.strain, 1) || ')');
        END IF;
    END IF;

    IF facts.weight_kg IS NOT NULL THEN
        health_parts := array_append(health_parts,
            'Weight: ' || ROUND(facts.weight_kg, 1) || 'kg');
    ELSE
        data_gaps := array_append(data_gaps, 'No weight recorded');
    END IF;

    -- FINANCE SUMMARY
    IF facts.transaction_count > 0 THEN
        IF facts.spend_total >= 500 THEN
            spend_label := 'high';
            finance_parts := array_append(finance_parts,
                'High spending day: ' || ROUND(facts.spend_total, 0) || ' AED across ' ||
                facts.transaction_count || ' transaction(s)');
            briefing_parts := array_append(briefing_parts,
                'spent ' || ROUND(facts.spend_total, 0) || ' AED (high)');
        ELSIF facts.spend_total >= 100 THEN
            spend_label := 'moderate';
            finance_parts := array_append(finance_parts,
                'Moderate spending: ' || ROUND(facts.spend_total, 0) || ' AED across ' ||
                facts.transaction_count || ' transaction(s)');
            briefing_parts := array_append(briefing_parts,
                'spent ' || ROUND(facts.spend_total, 0) || ' AED');
        ELSE
            spend_label := 'low';
            finance_parts := array_append(finance_parts,
                'Light spending: ' || ROUND(facts.spend_total, 0) || ' AED');
        END IF;

        IF facts.spend_groceries > 0 THEN
            finance_parts := array_append(finance_parts,
                'Groceries: ' || ROUND(facts.spend_groceries, 0) || ' AED');
        END IF;
        IF facts.spend_restaurants > 0 THEN
            finance_parts := array_append(finance_parts,
                'Dining: ' || ROUND(facts.spend_restaurants, 0) || ' AED');
        END IF;
        IF facts.spend_transport > 0 THEN
            finance_parts := array_append(finance_parts,
                'Transport: ' || ROUND(facts.spend_transport, 0) || ' AED');
        END IF;
        IF facts.income_total > 0 THEN
            finance_parts := array_append(finance_parts,
                'Income received: ' || ROUND(facts.income_total, 0) || ' AED');
        END IF;
    ELSE
        finance_parts := array_append(finance_parts, 'No transactions recorded');
    END IF;

    -- NUTRITION SUMMARY
    IF facts.meals_logged > 0 OR facts.water_ml > 0 THEN
        IF facts.meals_logged > 0 THEN
            nutrition_parts := array_append(nutrition_parts,
                facts.meals_logged || ' meal(s) logged');
            IF facts.calories_consumed IS NOT NULL THEN
                nutrition_parts := array_append(nutrition_parts,
                    facts.calories_consumed || ' calories');
            END IF;
            IF facts.protein_g IS NOT NULL THEN
                nutrition_parts := array_append(nutrition_parts,
                    facts.protein_g || 'g protein');
            END IF;
        END IF;
        IF facts.water_ml > 0 THEN
            nutrition_parts := array_append(nutrition_parts,
                ROUND(facts.water_ml / 1000.0, 1) || 'L water');
        END IF;
    ELSE
        data_gaps := array_append(data_gaps, 'No nutrition data logged');
    END IF;

    -- ACTIVITY SUMMARY
    IF facts.listening_minutes IS NOT NULL AND facts.listening_minutes > 0 THEN
        activity_parts := array_append(activity_parts,
            life.format_duration(facts.listening_minutes) || ' music across ' ||
            COALESCE(facts.listening_sessions, 1) || ' session(s)');
    END IF;
    IF facts.fasting_hours IS NOT NULL AND facts.fasting_hours > 0 THEN
        activity_parts := array_append(activity_parts,
            ROUND(facts.fasting_hours, 1) || 'h fasted');
    END IF;
    IF facts.reminders_completed > 0 THEN
        activity_parts := array_append(activity_parts,
            facts.reminders_completed || ' reminder(s) completed');
    END IF;
    IF facts.reminders_due > 0 AND facts.reminders_due > COALESCE(facts.reminders_completed, 0) THEN
        activity_parts := array_append(activity_parts,
            (facts.reminders_due - COALESCE(facts.reminders_completed, 0)) || ' reminder(s) pending');
    END IF;

    -- BUILD RESULT
    result := jsonb_build_object(
        'target_date', the_day,
        'has_data', TRUE,
        'health', jsonb_build_object(
            'recovery_label', recovery_label,
            'sleep_label', sleep_label,
            'recovery_score', facts.recovery_score,
            'sleep_hours', facts.sleep_hours,
            'hrv', facts.hrv,
            'strain', facts.strain,
            'weight_kg', facts.weight_kg,
            'summary', health_parts
        ),
        'finance', jsonb_build_object(
            'spend_label', spend_label,
            'spend_total', facts.spend_total,
            'transaction_count', facts.transaction_count,
            'summary', finance_parts
        ),
        'nutrition', jsonb_build_object(
            'meals_logged', facts.meals_logged,
            'calories', facts.calories_consumed,
            'protein_g', facts.protein_g,
            'water_ml', facts.water_ml,
            'summary', nutrition_parts
        ),
        'activity', jsonb_build_object(
            'listening_minutes', facts.listening_minutes,
            'fasting_hours', facts.fasting_hours,
            'reminders_due', facts.reminders_due,
            'reminders_completed', facts.reminders_completed,
            'summary', activity_parts
        ),
        'briefing', array_to_string(briefing_parts, ' after ') ||
            CASE WHEN array_length(briefing_parts, 1) > 0 THEN '.' ELSE '' END,
        'data_gaps', data_gaps,
        'data_completeness', facts.data_completeness,
        'computed_at', facts.computed_at,
        'assertions', assertions
    );

    RETURN result;
END;
$function$;

COMMENT ON FUNCTION life.explain_today IS 'v1: Basic daily briefing with recovery/sleep/spend classification';

DELETE FROM ops.schema_migrations WHERE filename = '182_smart_briefing.up.sql';

COMMIT;
