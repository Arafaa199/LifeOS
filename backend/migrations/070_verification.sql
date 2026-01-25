-- Verification queries for TASK-VERIFY.1: Data Coverage Audit

-- 1. View last 30 days coverage percentage per domain
SELECT * FROM life.v_coverage_summary_30d;

-- 2. Check specific gap scenarios (last 7 days)
SELECT day,
       has_sms_no_transaction,
       has_groceries_no_food_log,
       has_whoop_no_daily_facts,
       has_transactions_no_summary
FROM life.v_data_coverage_gaps
WHERE day >= CURRENT_DATE - INTERVAL '7 days'
  AND (has_sms_no_transaction OR has_groceries_no_food_log OR has_whoop_no_daily_facts OR has_transactions_no_summary)
ORDER BY day DESC;

-- 3. Show overall data presence for last 7 days
SELECT day,
       has_sms, has_transactions, has_receipts, has_receipt_items,
       has_food_log, has_whoop, has_daily_facts, has_daily_summary
FROM life.v_data_coverage_gaps
WHERE day >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY day DESC;

-- 4. Domain coverage matrix for last 7 days
SELECT day,
       finance_transactions, finance_receipts,
       health_whoop, health_body_metrics,
       nutrition_food, nutrition_water,
       behavioral_location, behavioral_events,
       productivity_github, productivity_calendar,
       aggregated_daily_facts
FROM life.v_domain_coverage_matrix
WHERE day >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY day DESC;

-- 5. Count gaps by type (last 30 days)
SELECT
    COUNT(*) FILTER (WHERE has_sms_no_transaction) as sms_no_tx_gaps,
    COUNT(*) FILTER (WHERE has_groceries_no_food_log) as groceries_no_food_gaps,
    COUNT(*) FILTER (WHERE has_whoop_no_daily_facts) as whoop_no_facts_gaps,
    COUNT(*) FILTER (WHERE has_transactions_no_summary) as tx_no_summary_gaps
FROM life.v_data_coverage_gaps
WHERE day >= CURRENT_DATE - INTERVAL '30 days';
