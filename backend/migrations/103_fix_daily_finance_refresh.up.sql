-- Migration 103: Rewrite facts.refresh_daily_finance() to read from finance.transactions
-- Problem: Function reads from normalized.transactions (0 rows). Actual data is in finance.transactions (1366+ rows).
-- Also wires into life.refresh_all() for nightly auto-refresh.

BEGIN;

-- 1. Rewrite refresh function to use finance.transactions
CREATE OR REPLACE FUNCTION facts.refresh_daily_finance(target_date date)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO facts.daily_finance (
        date,
        total_spent, total_income, net_flow,
        grocery_spent, food_delivery_spent, restaurant_spent,
        transport_spent, utilities_spent, shopping_spent,
        subscriptions_spent, other_spent,
        transaction_count, expense_count, income_count,
        refreshed_at
    )
    SELECT
        target_date,
        -- total_spent: sum of negative amounts (expenses), stored as positive
        COALESCE(SUM(CASE WHEN amount < 0 AND category NOT IN ('Transfer', 'Credit Card Payment') THEN ABS(amount) END), 0),
        -- total_income: sum of positive amounts in income-like categories
        COALESCE(SUM(CASE WHEN category IN ('Income', 'Salary', 'Deposit', 'Refund') AND amount > 0 THEN amount END), 0),
        -- net_flow: income - expenses
        COALESCE(SUM(CASE WHEN category IN ('Income', 'Salary', 'Deposit', 'Refund') AND amount > 0 THEN amount END), 0)
          - COALESCE(SUM(CASE WHEN amount < 0 AND category NOT IN ('Transfer', 'Credit Card Payment') THEN ABS(amount) END), 0),
        -- Category breakdowns (expenses stored as positive values)
        COALESCE(SUM(CASE WHEN category = 'Grocery' AND amount < 0 THEN ABS(amount) END), 0),
        COALESCE(SUM(CASE WHEN category = 'Food' AND amount < 0 THEN ABS(amount) END), 0),
        COALESCE(SUM(CASE WHEN category IN ('Restaurant') AND amount < 0 THEN ABS(amount) END), 0),
        COALESCE(SUM(CASE WHEN category = 'Transport' AND amount < 0 THEN ABS(amount) END), 0),
        COALESCE(SUM(CASE WHEN category IN ('Utilities', 'Bills') AND amount < 0 THEN ABS(amount) END), 0),
        COALESCE(SUM(CASE WHEN category = 'Shopping' AND amount < 0 THEN ABS(amount) END), 0),
        COALESCE(SUM(CASE WHEN category IN ('Entertainment') AND amount < 0 THEN ABS(amount) END), 0),
        -- other_spent: expenses not in above categories
        COALESCE(SUM(CASE WHEN amount < 0
                          AND category NOT IN ('Grocery', 'Food', 'Restaurant', 'Transport',
                                               'Utilities', 'Bills', 'Shopping', 'Entertainment',
                                               'Transfer', 'Credit Card Payment',
                                               'Income', 'Salary', 'Deposit', 'Refund')
                          THEN ABS(amount) END), 0),
        -- Counts
        COUNT(*)::INT,
        COUNT(CASE WHEN amount < 0 AND category NOT IN ('Transfer', 'Credit Card Payment') THEN 1 END)::INT,
        COUNT(CASE WHEN category IN ('Income', 'Salary', 'Deposit', 'Refund') AND amount > 0 THEN 1 END)::INT,
        NOW()
    FROM finance.transactions
    WHERE date = target_date
      AND is_hidden IS NOT TRUE
      AND is_quarantined IS NOT TRUE
    GROUP BY target_date
    ON CONFLICT (date) DO UPDATE SET
        total_spent = EXCLUDED.total_spent,
        total_income = EXCLUDED.total_income,
        net_flow = EXCLUDED.net_flow,
        grocery_spent = EXCLUDED.grocery_spent,
        food_delivery_spent = EXCLUDED.food_delivery_spent,
        restaurant_spent = EXCLUDED.restaurant_spent,
        transport_spent = EXCLUDED.transport_spent,
        utilities_spent = EXCLUDED.utilities_spent,
        shopping_spent = EXCLUDED.shopping_spent,
        subscriptions_spent = EXCLUDED.subscriptions_spent,
        other_spent = EXCLUDED.other_spent,
        transaction_count = EXCLUDED.transaction_count,
        expense_count = EXCLUDED.expense_count,
        income_count = EXCLUDED.income_count,
        refreshed_at = NOW();

    -- Handle days with no transactions (ensure row exists)
    INSERT INTO facts.daily_finance (date, refreshed_at)
    VALUES (target_date, NOW())
    ON CONFLICT (date) DO NOTHING;
END;
$function$;

-- 2. Wire into life.refresh_all(p_days, p_caller) — the jsonb-returning overload
CREATE OR REPLACE FUNCTION life.refresh_all(p_days integer DEFAULT 1, p_caller text DEFAULT 'manual'::text)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    v_start DATE;
    v_end DATE;
    v_day DATE;
    v_refreshed INTEGER := 0;
    v_errors INTEGER := 0;
    v_result JSONB;
BEGIN
    PERFORM life.reset_feed_events_today();

    v_end := life.dubai_today();
    v_start := v_end - (p_days - 1);

    FOR v_day IN SELECT generate_series(v_start, v_end, '1 day'::interval)::date
    LOOP
        BEGIN
            PERFORM life.refresh_daily_facts(v_day);
            v_refreshed := v_refreshed + 1;
        EXCEPTION WHEN OTHERS THEN
            v_errors := v_errors + 1;
            INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
            VALUES ('life.refresh_all', 'life.daily_facts',
                    SQLERRM, format('day=%s caller=%s', v_day, p_caller));
            RAISE NOTICE 'refresh_all: failed for % — %', v_day, SQLERRM;
        END;

        BEGIN
            PERFORM facts.refresh_daily_health(v_day);
        EXCEPTION WHEN OTHERS THEN
            v_errors := v_errors + 1;
            INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
            VALUES ('life.refresh_all', 'facts.daily_health',
                    SQLERRM, format('day=%s caller=%s', v_day, p_caller));
            RAISE NOTICE 'refresh_all: facts.refresh_daily_health failed for % — %', v_day, SQLERRM;
        END;

        -- Refresh daily finance for this day
        BEGIN
            PERFORM facts.refresh_daily_finance(v_day);
        EXCEPTION WHEN OTHERS THEN
            v_errors := v_errors + 1;
            INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
            VALUES ('life.refresh_all', 'facts.daily_finance',
                    SQLERRM, format('day=%s caller=%s', v_day, p_caller));
            RAISE NOTICE 'refresh_all: facts.refresh_daily_finance failed for % — %', v_day, SQLERRM;
        END;
    END LOOP;

    BEGIN
        PERFORM finance.refresh_financial_truth();
    EXCEPTION WHEN OTHERS THEN
        v_errors := v_errors + 1;
        INSERT INTO ops.trigger_errors (trigger_name, table_name, error_message, error_detail)
        VALUES ('life.refresh_all', 'finance.mv_*', SQLERRM, format('caller=%s', p_caller));
        RAISE NOTICE 'refresh_all: finance.refresh_financial_truth() failed — %', SQLERRM;
    END;

    v_result := jsonb_build_object(
        'refreshed_days', v_refreshed,
        'errors', v_errors,
        'range', format('%s..%s', v_start, v_end),
        'caller', p_caller,
        'completed_at', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
    );

    RAISE NOTICE 'refresh_all complete: %', v_result;
    RETURN v_result;
END;
$function$;

-- 3. Wire into life.refresh_all(days_back, triggered_by) — the TABLE-returning overload
CREATE OR REPLACE FUNCTION life.refresh_all(days_back integer DEFAULT 2, triggered_by character varying DEFAULT 'manual'::character varying)
RETURNS TABLE(day date, status text, rows_affected integer, duration_ms integer)
LANGUAGE plpgsql
AS $function$
DECLARE
    d DATE;
    result RECORD;
    today_dubai DATE := life.dubai_today();
BEGIN
    PERFORM life.reset_feed_events_today();

    FOR d IN SELECT generate_series(
        today_dubai - days_back,
        today_dubai,
        '1 day'::interval
    )::date
    LOOP
        SELECT * INTO result FROM life.refresh_daily_facts(d, triggered_by);
        RETURN QUERY SELECT d, result.status, result.rows_affected, result.duration_ms;

        BEGIN
            PERFORM facts.refresh_daily_health(d);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'refresh_all: facts.refresh_daily_health failed for % — %', d, SQLERRM;
        END;

        -- Refresh daily finance for this day
        BEGIN
            PERFORM facts.refresh_daily_finance(d);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'refresh_all: facts.refresh_daily_finance failed for % — %', d, SQLERRM;
        END;
    END LOOP;

    PERFORM life.refresh_baselines(triggered_by);

    RETURN;
END;
$function$;

-- 4. Backfill all historical dates
DO $$
DECLARE
    v_date DATE;
    v_count INTEGER := 0;
BEGIN
    -- Clear any stale data
    DELETE FROM facts.daily_finance;

    FOR v_date IN
        SELECT DISTINCT date
        FROM finance.transactions
        WHERE date IS NOT NULL
        ORDER BY date
    LOOP
        BEGIN
            PERFORM facts.refresh_daily_finance(v_date);
            v_count := v_count + 1;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Backfill failed for %: %', v_date, SQLERRM;
        END;
    END LOOP;

    RAISE NOTICE 'Backfilled % dates into facts.daily_finance', v_count;
END;
$$;

COMMIT;
