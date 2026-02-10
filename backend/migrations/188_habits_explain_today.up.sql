BEGIN;

-- ============================================================================
-- Migration 188: Add habit streak observations to explain_today()
-- If any habit streak >= 7 days, mention positively (P3).
-- If any streak broke yesterday (was active but no completion), mention as warning (P2).
-- ============================================================================

CREATE OR REPLACE FUNCTION life.explain_today(target_date date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    the_day DATE;
    facts RECORD;
    result JSONB;

    -- Structured section summaries (for detail views)
    health_parts TEXT[] := '{}';
    finance_parts TEXT[] := '{}';
    nutrition_parts TEXT[] := '{}';
    activity_parts TEXT[] := '{}';
    data_gaps TEXT[] := '{}';

    -- Priority-ranked observations stored as jsonb array of {p: int, t: text}
    obs JSONB := '[]'::jsonb;

    -- 7-day trends
    recovery_avg_7d NUMERIC;
    recovery_vs_7d NUMERIC;
    sleep_avg_7d NUMERIC;
    sleep_vs_7d NUMERIC;
    spend_avg_7d NUMERIC;
    calories_avg_7d NUMERIC;

    -- BJJ context
    bjj_last_date DATE;
    days_since_bjj INT;
    bjj_streak INT := 0;
    bjj_sessions_week INT := 0;
    day_of_week INT;

    -- Labels
    recovery_label TEXT;
    sleep_label TEXT;
    spend_label TEXT;

    -- Assertions
    assertions JSONB;
    dubai_check BOOLEAN;
    freshness_check BOOLEAN;
    completeness_check BOOLEAN;

    -- Briefing assembly
    final_observations TEXT[];
    max_priority INT;
    briefing TEXT;

    -- Habit streaks
    v_habit_rec RECORD;
    v_milestone_habits TEXT[];
    v_broken_habits TEXT[];
BEGIN
    the_day := COALESCE(target_date, life.dubai_today());

    -- ======================================================================
    -- ASSERTIONS (unchanged from v1)
    -- ======================================================================
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
            'briefing', 'No data recorded for ' || to_char(the_day, 'FMMonth DD') || '.',
            'data_gaps', ARRAY['No daily_facts row exists for this date'],
            'assertions', assertions
        );
    END IF;

    -- ======================================================================
    -- 7-DAY BASELINES (single query)
    -- ======================================================================
    SELECT
        AVG(recovery_score),
        AVG(sleep_hours),
        AVG(spend_total),
        AVG(calories_consumed)
    INTO recovery_avg_7d, sleep_avg_7d, spend_avg_7d, calories_avg_7d
    FROM life.daily_facts
    WHERE day BETWEEN the_day - 7 AND the_day - 1;

    IF recovery_avg_7d > 0 AND facts.recovery_score IS NOT NULL THEN
        recovery_vs_7d := ROUND(((facts.recovery_score - recovery_avg_7d) / recovery_avg_7d * 100)::numeric, 0);
    END IF;

    IF sleep_avg_7d > 0 AND facts.sleep_hours IS NOT NULL THEN
        sleep_vs_7d := ROUND(((facts.sleep_hours - sleep_avg_7d) / sleep_avg_7d * 100)::numeric, 0);
    END IF;

    -- ======================================================================
    -- BJJ CONTEXT
    -- ======================================================================
    day_of_week := EXTRACT(ISODOW FROM the_day)::INT;

    SELECT session_date INTO bjj_last_date
    FROM health.bjj_sessions ORDER BY session_date DESC LIMIT 1;

    IF bjj_last_date IS NOT NULL THEN
        days_since_bjj := the_day - bjj_last_date;
    END IF;

    BEGIN
        SELECT current_streak, sessions_this_week
        INTO bjj_streak, bjj_sessions_week
        FROM health.get_bjj_streaks();
    EXCEPTION WHEN OTHERS THEN
        bjj_streak := 0; bjj_sessions_week := 0;
    END;

    -- ======================================================================
    -- SCORE & COLLECT OBSERVATIONS
    -- ======================================================================

    -- ── RECOVERY ──────────────────────────────────────────────────────────
    IF facts.recovery_score IS NOT NULL THEN
        IF facts.recovery_score < 34 THEN
            recovery_label := 'low';
            IF facts.deep_sleep_minutes IS NOT NULL AND facts.deep_sleep_minutes < 45 THEN
                obs := obs || jsonb_build_object('p', 9, 't',
                    'Recovery at ' || facts.recovery_score || '%, deep sleep was only ' ||
                    facts.deep_sleep_minutes || ' min — take it easy today.');
            ELSE
                obs := obs || jsonb_build_object('p', 9, 't',
                    'Recovery is low at ' || facts.recovery_score || '% — prioritize rest.');
            END IF;
        ELSIF recovery_vs_7d IS NOT NULL AND recovery_vs_7d < -10 THEN
            recovery_label := CASE WHEN facts.recovery_score >= 67 THEN 'high' ELSE 'moderate' END;
            IF facts.deep_sleep_minutes IS NOT NULL AND facts.deep_sleep_minutes < 45 THEN
                obs := obs || jsonb_build_object('p', 8, 't',
                    'Recovery at ' || facts.recovery_score || '%, down ' ||
                    ABS(recovery_vs_7d)::INT::TEXT || '% from your 7-day average — deep sleep was only ' ||
                    facts.deep_sleep_minutes || ' min.');
            ELSE
                obs := obs || jsonb_build_object('p', 7, 't',
                    'Recovery at ' || facts.recovery_score || '%, down ' ||
                    ABS(recovery_vs_7d)::INT::TEXT || '% from your 7-day average.');
            END IF;
        ELSIF facts.recovery_score >= 67 THEN
            recovery_label := 'high';
            obs := obs || jsonb_build_object('p', 3, 't',
                'Recovery is strong at ' || facts.recovery_score || '%.');
        ELSE
            recovery_label := 'moderate';
        END IF;
        health_parts := array_append(health_parts,
            'Recovery: ' || facts.recovery_score || '% (' || recovery_label || ')');
    ELSE
        data_gaps := array_append(data_gaps, 'Recovery score not available');
    END IF;

    -- ── SLEEP ─────────────────────────────────────────────────────────────
    IF facts.sleep_hours IS NOT NULL THEN
        IF facts.sleep_hours < 6 THEN
            sleep_label := 'poor';
            obs := obs || jsonb_build_object('p', 8, 't',
                'Only ' || ROUND(facts.sleep_hours, 1) || 'h sleep — you''ll feel it.');
        ELSIF facts.deep_sleep_minutes IS NOT NULL AND facts.deep_sleep_minutes < 45
              AND (facts.recovery_score IS NULL OR facts.recovery_score >= 34) THEN
            sleep_label := 'poor quality';
            obs := obs || jsonb_build_object('p', 7, 't',
                'Sleep quality was poor — only ' || facts.deep_sleep_minutes || ' min deep sleep.');
        ELSIF facts.sleep_efficiency IS NOT NULL AND facts.sleep_efficiency < 0.80 THEN
            sleep_label := 'poor quality';
            obs := obs || jsonb_build_object('p', 7, 't',
                'Sleep efficiency low at ' || ROUND(facts.sleep_efficiency * 100)::TEXT || '%.');
        ELSIF sleep_vs_7d IS NOT NULL AND sleep_vs_7d < -10 THEN
            sleep_label := 'declining';
            obs := obs || jsonb_build_object('p', 6, 't',
                'Sleep trending down — ' || ROUND(facts.sleep_hours, 1) || 'h vs ' ||
                ROUND(sleep_avg_7d, 1) || 'h average.');
        ELSIF facts.sleep_hours >= 7.5 THEN
            sleep_label := 'good';
            obs := obs || jsonb_build_object('p', 2, 't',
                ROUND(facts.sleep_hours, 1) || 'h of solid sleep.');
        ELSE
            sleep_label := 'fair';
        END IF;
        health_parts := array_append(health_parts,
            'Sleep: ' || ROUND(facts.sleep_hours, 1) || 'h (' || sleep_label || ')');
        IF facts.deep_sleep_minutes IS NOT NULL THEN
            health_parts := array_append(health_parts, 'Deep sleep: ' || facts.deep_sleep_minutes || ' min');
        END IF;
        IF facts.rem_sleep_minutes IS NOT NULL THEN
            health_parts := array_append(health_parts, 'REM sleep: ' || facts.rem_sleep_minutes || ' min');
        END IF;
    ELSE
        data_gaps := array_append(data_gaps, 'Sleep data not available');
    END IF;

    -- ── SPEND ─────────────────────────────────────────────────────────────
    IF facts.spend_total IS NOT NULL AND facts.spend_total > 0 THEN
        IF spend_avg_7d IS NOT NULL AND spend_avg_7d > 0
           AND facts.spend_total > spend_avg_7d * 1.5 THEN
            spend_label := 'unusual';
            IF facts.spend_groceries > facts.spend_total * 0.5 THEN
                obs := obs || jsonb_build_object('p', 8, 't',
                    'Unusual spending: ' || ROUND(facts.spend_total)::TEXT ||
                    ' AED vs your ' || ROUND(spend_avg_7d)::TEXT ||
                    ' average — groceries drove most of it.');
            ELSIF facts.spend_restaurants > facts.spend_total * 0.5 THEN
                obs := obs || jsonb_build_object('p', 8, 't',
                    'Unusual spending: ' || ROUND(facts.spend_total)::TEXT ||
                    ' AED vs your ' || ROUND(spend_avg_7d)::TEXT ||
                    ' average — dining out was the main driver.');
            ELSE
                obs := obs || jsonb_build_object('p', 8, 't',
                    'Unusual spending: ' || ROUND(facts.spend_total)::TEXT ||
                    ' AED vs your ' || ROUND(spend_avg_7d)::TEXT || ' average.');
            END IF;
        ELSIF facts.spend_total >= 500 THEN
            spend_label := 'high';
            obs := obs || jsonb_build_object('p', 5, 't',
                'Heavy spend day: ' || ROUND(facts.spend_total)::TEXT || ' AED.');
        ELSE
            spend_label := 'normal';
        END IF;
        finance_parts := array_append(finance_parts,
            'Spend: ' || ROUND(facts.spend_total)::TEXT || ' AED (' || COALESCE(spend_label, 'normal') || ')');
    END IF;

    -- ── BJJ ───────────────────────────────────────────────────────────────
    IF days_since_bjj IS NOT NULL AND days_since_bjj = 0 THEN
        obs := obs || jsonb_build_object('p', 4, 't', 'BJJ session logged today — nice work.');
    ELSIF days_since_bjj IS NOT NULL AND days_since_bjj = 1 THEN
        IF facts.recovery_score IS NOT NULL THEN
            IF facts.recovery_score >= 67 THEN
                obs := obs || jsonb_build_object('p', 6, 't',
                    'BJJ yesterday' ||
                    CASE WHEN bjj_streak > 1 THEN ', ' || bjj_streak || '-week streak'
                    ELSE '' END ||
                    '. Recovery at ' || facts.recovery_score || '% — good to go again.');
            ELSIF facts.recovery_score >= 34 THEN
                obs := obs || jsonb_build_object('p', 6, 't',
                    'BJJ yesterday — recovery at ' || facts.recovery_score ||
                    '% is moderate, listen to your body.');
            ELSE
                obs := obs || jsonb_build_object('p', 8, 't',
                    'BJJ yesterday and recovery is low (' || facts.recovery_score ||
                    '%) — consider a rest day.');
            END IF;
        ELSE
            obs := obs || jsonb_build_object('p', 4, 't', 'Trained BJJ yesterday.');
        END IF;
    ELSIF bjj_streak > 1 AND days_since_bjj IS NOT NULL AND days_since_bjj <= 3 THEN
        obs := obs || jsonb_build_object('p', 3, 't',
            bjj_streak || '-week training streak going.');
    END IF;

    IF bjj_sessions_week = 0 AND day_of_week >= 4 THEN
        obs := obs || jsonb_build_object('p', 6, 't',
            'No training yet this week — ' ||
            CASE day_of_week
                WHEN 4 THEN 'Thursday already.'
                WHEN 5 THEN 'Friday already.'
                WHEN 6 THEN 'Saturday, last chance.'
                WHEN 7 THEN 'week''s almost over.'
            END);
    END IF;

    -- ── NUTRITION ─────────────────────────────────────────────────────────
    IF facts.protein_g IS NOT NULL AND facts.protein_g < 120 AND facts.meals_logged > 0 THEN
        obs := obs || jsonb_build_object('p', 6, 't',
            'Protein low at ' || facts.protein_g || 'g, aim for 120+.');
    END IF;

    IF facts.calories_consumed IS NOT NULL AND calories_avg_7d IS NOT NULL AND calories_avg_7d > 0 THEN
        IF facts.calories_consumed < calories_avg_7d * 0.6 AND facts.meals_logged > 0 THEN
            obs := obs || jsonb_build_object('p', 6, 't',
                'Calories are low at ' || facts.calories_consumed || ' kcal.');
        ELSIF facts.calories_consumed > calories_avg_7d * 1.4 THEN
            obs := obs || jsonb_build_object('p', 5, 't',
                'High calorie day: ' || facts.calories_consumed || ' kcal vs ' ||
                ROUND(calories_avg_7d)::TEXT || ' avg.');
        END IF;
    END IF;

    -- ── MOOD / ENERGY ─────────────────────────────────────────────────────
    IF facts.avg_mood IS NOT NULL AND facts.avg_mood < 5 THEN
        obs := obs || jsonb_build_object('p', 6, 't',
            'Mood is on the lower side (' || ROUND(facts.avg_mood, 1) || '/10).');
    END IF;
    IF facts.avg_energy IS NOT NULL AND facts.avg_energy < 5 THEN
        obs := obs || jsonb_build_object('p', 6, 't',
            'Energy is low (' || ROUND(facts.avg_energy, 1) || '/10) — pace yourself.');
    END IF;

    -- ── HABIT STREAKS (new in v3) ─────────────────────────────────────────
    v_milestone_habits := '{}';
    v_broken_habits := '{}';

    BEGIN
        FOR v_habit_rec IN
            SELECT h.name, s.current_streak, s.longest_streak
            FROM life.habits h
            CROSS JOIN LATERAL life.get_habit_streaks(h.id) s
            WHERE h.is_active = TRUE
        LOOP
            -- Milestone: streak >= 7 days
            IF v_habit_rec.current_streak >= 7 THEN
                v_milestone_habits := array_append(v_milestone_habits,
                    v_habit_rec.name || ' ' || v_habit_rec.current_streak || 'd');
            END IF;

            -- Broken: had a streak yesterday (longest > current and current = 0)
            -- i.e., they were completing but missed today (if it's late enough to matter)
            -- More precisely: check if yesterday had a completion but today doesn't
            IF v_habit_rec.current_streak = 0 AND v_habit_rec.longest_streak >= 3 THEN
                -- Check if they completed yesterday but not today
                IF EXISTS(
                    SELECT 1 FROM life.habit_completions hc
                    JOIN life.habits hh ON hh.id = hc.habit_id AND hh.name = v_habit_rec.name
                    WHERE (hc.completed_at AT TIME ZONE 'Asia/Dubai')::date = the_day - 1
                ) AND NOT EXISTS(
                    SELECT 1 FROM life.habit_completions hc
                    JOIN life.habits hh ON hh.id = hc.habit_id AND hh.name = v_habit_rec.name
                    WHERE (hc.completed_at AT TIME ZONE 'Asia/Dubai')::date = the_day
                ) THEN
                    v_broken_habits := array_append(v_broken_habits, v_habit_rec.name);
                END IF;
            END IF;
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        -- Habits table might not exist yet in transition
        NULL;
    END;

    -- Report broken streaks (P2 = medium, watch out)
    IF array_length(v_broken_habits, 1) > 0 THEN
        obs := obs || jsonb_build_object('p', 7, 't',
            'Streak at risk: ' || array_to_string(v_broken_habits, ', ') ||
            ' — don''t let it slip.');
    END IF;

    -- Report milestone streaks (P3 = positive)
    IF array_length(v_milestone_habits, 1) > 0 THEN
        obs := obs || jsonb_build_object('p', 3, 't',
            'Strong streaks: ' || array_to_string(v_milestone_habits, ', ') || '.');
    END IF;

    -- ======================================================================
    -- ASSEMBLE BRIEFING: top 5 observations sorted by priority
    -- ======================================================================
    SELECT array_agg(t ORDER BY p DESC), MAX(p)
    INTO final_observations, max_priority
    FROM (
        SELECT elem->>'t' AS t, (elem->>'p')::int AS p
        FROM jsonb_array_elements(obs) elem
        ORDER BY (elem->>'p')::int DESC
        LIMIT 5
    ) top;

    IF final_observations IS NULL OR array_length(final_observations, 1) IS NULL THEN
        briefing := 'Solid day across the board — recovery, sleep, and spending all tracking normally.';
    ELSIF max_priority <= 3 THEN
        briefing := 'Solid day across the board. ' || array_to_string(final_observations, ' ');
    ELSE
        briefing := array_to_string(final_observations, ' ');
    END IF;

    -- ======================================================================
    -- STRUCTURED SECTIONS (detail views — always populated)
    -- ======================================================================
    IF facts.hrv IS NOT NULL THEN
        health_parts := array_append(health_parts, 'HRV: ' || ROUND(facts.hrv)::TEXT || 'ms');
    END IF;
    IF facts.strain IS NOT NULL THEN
        health_parts := array_append(health_parts, 'Strain: ' || ROUND(facts.strain, 1)::TEXT);
    END IF;
    IF facts.weight_kg IS NOT NULL THEN
        health_parts := array_append(health_parts, 'Weight: ' || ROUND(facts.weight_kg, 1)::TEXT || 'kg');
    ELSE
        data_gaps := array_append(data_gaps, 'No weight recorded');
    END IF;

    IF facts.spend_groceries > 0 THEN
        finance_parts := array_append(finance_parts, 'Groceries: ' || ROUND(facts.spend_groceries)::TEXT || ' AED');
    END IF;
    IF facts.spend_restaurants > 0 THEN
        finance_parts := array_append(finance_parts, 'Dining: ' || ROUND(facts.spend_restaurants)::TEXT || ' AED');
    END IF;
    IF facts.spend_transport > 0 THEN
        finance_parts := array_append(finance_parts, 'Transport: ' || ROUND(facts.spend_transport)::TEXT || ' AED');
    END IF;
    IF facts.income_total > 0 THEN
        finance_parts := array_append(finance_parts, 'Income: ' || ROUND(facts.income_total)::TEXT || ' AED');
    END IF;

    IF facts.meals_logged > 0 THEN
        nutrition_parts := array_append(nutrition_parts, facts.meals_logged || ' meal(s)');
        IF facts.calories_consumed IS NOT NULL THEN
            nutrition_parts := array_append(nutrition_parts, facts.calories_consumed || ' kcal');
        END IF;
        IF facts.protein_g IS NOT NULL THEN
            nutrition_parts := array_append(nutrition_parts, facts.protein_g || 'g protein');
        END IF;
    ELSE
        data_gaps := array_append(data_gaps, 'No nutrition data logged');
    END IF;
    IF facts.water_ml > 0 THEN
        nutrition_parts := array_append(nutrition_parts, ROUND(facts.water_ml / 1000.0, 1) || 'L water');
    END IF;

    IF facts.listening_minutes IS NOT NULL AND facts.listening_minutes > 0 THEN
        activity_parts := array_append(activity_parts, life.format_duration(facts.listening_minutes) || ' music');
    END IF;
    IF facts.fasting_hours IS NOT NULL AND facts.fasting_hours > 0 THEN
        activity_parts := array_append(activity_parts, ROUND(facts.fasting_hours, 1) || 'h fasted');
    END IF;
    IF facts.reminders_completed > 0 THEN
        activity_parts := array_append(activity_parts, facts.reminders_completed || ' reminder(s) done');
    END IF;

    -- ======================================================================
    -- RETURN (same shape as v2)
    -- ======================================================================
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
        'briefing', briefing,
        'data_gaps', data_gaps,
        'data_completeness', facts.data_completeness,
        'computed_at', facts.computed_at,
        'assertions', assertions
    );

    RETURN result;
END;
$function$;

COMMENT ON FUNCTION life.explain_today IS 'v3: Priority-ranked coach briefing — adds habit streak observations (milestone >= 7d at P3, broken at P7). Same return shape as v2.';

INSERT INTO ops.schema_migrations (filename)
VALUES ('188_habits_explain_today.up.sql')
ON CONFLICT (filename) DO NOTHING;

COMMIT;
