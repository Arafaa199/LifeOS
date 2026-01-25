-- Migration: Data Coverage Audit Views
-- Purpose: Identify gaps where data exists in one domain but not others
-- Task: TASK-VERIFY.1

-- Create life.v_data_coverage_gaps view showing specific gap scenarios
CREATE OR REPLACE VIEW life.v_data_coverage_gaps AS
WITH date_range AS (
    -- Last 90 days
    SELECT generate_series(
        CURRENT_DATE - INTERVAL '90 days',
        CURRENT_DATE,
        '1 day'::interval
    )::date as day
),
sms_days AS (
    -- Days with SMS-sourced transactions (via raw_events link)
    SELECT DISTINCT (t.transaction_at AT TIME ZONE 'Asia/Dubai')::date as day
    FROM finance.transactions t
    INNER JOIN finance.raw_events re ON t.id = re.related_transaction_id
    WHERE re.event_type LIKE '%sms%' OR re.source = 'sms'
),
transaction_days AS (
    SELECT DISTINCT (transaction_at AT TIME ZONE 'Asia/Dubai')::date as day
    FROM finance.transactions
),
receipt_days AS (
    SELECT DISTINCT receipt_date as day
    FROM finance.receipts
    WHERE parse_status = 'success'
),
receipt_items_days AS (
    SELECT DISTINCT r.receipt_date as day
    FROM finance.receipts r
    INNER JOIN finance.receipt_items ri ON r.id = ri.receipt_id
),
food_log_days AS (
    SELECT DISTINCT (logged_at AT TIME ZONE 'Asia/Dubai')::date as day
    FROM nutrition.food_log
),
whoop_days AS (
    SELECT DISTINCT (recorded_at AT TIME ZONE 'Asia/Dubai')::date as day
    FROM health.metrics
    WHERE metric_type IN ('recovery_score', 'hrv', 'sleep_hours')
),
daily_facts_days AS (
    SELECT DISTINCT day
    FROM life.daily_facts
),
daily_summary_days AS (
    -- Days where life.get_daily_summary() would return valid data
    SELECT DISTINCT day
    FROM life.daily_facts
    WHERE spend_total IS NOT NULL OR recovery_score IS NOT NULL
)
SELECT
    dr.day,
    -- Gap scenarios
    CASE WHEN sd.day IS NOT NULL AND td.day IS NULL THEN true ELSE false END as has_sms_no_transaction,
    CASE WHEN rid.day IS NOT NULL AND fl.day IS NULL THEN true ELSE false END as has_groceries_no_food_log,
    CASE WHEN wd.day IS NOT NULL AND df.day IS NULL THEN true ELSE false END as has_whoop_no_daily_facts,
    CASE WHEN td.day IS NOT NULL AND ds.day IS NULL THEN true ELSE false END as has_transactions_no_summary,
    -- Raw coverage indicators
    sd.day IS NOT NULL as has_sms,
    td.day IS NOT NULL as has_transactions,
    rd.day IS NOT NULL as has_receipts,
    rid.day IS NOT NULL as has_receipt_items,
    fl.day IS NOT NULL as has_food_log,
    wd.day IS NOT NULL as has_whoop,
    df.day IS NOT NULL as has_daily_facts,
    ds.day IS NOT NULL as has_daily_summary
FROM date_range dr
LEFT JOIN sms_days sd ON dr.day = sd.day
LEFT JOIN transaction_days td ON dr.day = td.day
LEFT JOIN receipt_days rd ON dr.day = rd.day
LEFT JOIN receipt_items_days rid ON dr.day = rid.day
LEFT JOIN food_log_days fl ON dr.day = fl.day
LEFT JOIN whoop_days wd ON dr.day = wd.day
LEFT JOIN daily_facts_days df ON dr.day = df.day
LEFT JOIN daily_summary_days ds ON dr.day = ds.day
ORDER BY dr.day DESC;

COMMENT ON VIEW life.v_data_coverage_gaps IS
'Shows specific gap scenarios where data exists in one domain but is missing in related domains';


-- Create life.v_domain_coverage_matrix showing coverage by domain by day
CREATE OR REPLACE VIEW life.v_domain_coverage_matrix AS
WITH date_range AS (
    SELECT generate_series(
        CURRENT_DATE - INTERVAL '90 days',
        CURRENT_DATE,
        '1 day'::interval
    )::date as day
)
SELECT
    dr.day,
    -- Finance domain
    EXISTS(SELECT 1 FROM finance.transactions t WHERE (t.transaction_at AT TIME ZONE 'Asia/Dubai')::date = dr.day) as finance_transactions,
    EXISTS(SELECT 1 FROM finance.receipts r WHERE r.receipt_date = dr.day) as finance_receipts,
    -- Health domain
    EXISTS(SELECT 1 FROM health.metrics m WHERE (m.recorded_at AT TIME ZONE 'Asia/Dubai')::date = dr.day AND m.metric_type IN ('recovery_score', 'hrv')) as health_whoop,
    EXISTS(SELECT 1 FROM health.body_measurements bm WHERE bm.date = dr.day) as health_body_metrics,
    -- Nutrition domain
    EXISTS(SELECT 1 FROM nutrition.food_log fl WHERE (fl.logged_at AT TIME ZONE 'Asia/Dubai')::date = dr.day) as nutrition_food,
    EXISTS(SELECT 1 FROM nutrition.water_log wl WHERE (wl.logged_at AT TIME ZONE 'Asia/Dubai')::date = dr.day) as nutrition_water,
    -- Behavioral domain
    EXISTS(SELECT 1 FROM life.locations l WHERE (l.recorded_at AT TIME ZONE 'Asia/Dubai')::date = dr.day) as behavioral_location,
    EXISTS(SELECT 1 FROM life.behavioral_events be WHERE (be.recorded_at AT TIME ZONE 'Asia/Dubai')::date = dr.day) as behavioral_events,
    -- Productivity domain
    EXISTS(SELECT 1 FROM raw.github_events ge WHERE (ge.created_at_github AT TIME ZONE 'Asia/Dubai')::date = dr.day) as productivity_github,
    EXISTS(SELECT 1 FROM raw.calendar_events ce WHERE (ce.start_at AT TIME ZONE 'Asia/Dubai')::date = dr.day) as productivity_calendar,
    -- Aggregated domain
    EXISTS(SELECT 1 FROM life.daily_facts df WHERE df.day = dr.day) as aggregated_daily_facts
FROM date_range dr
ORDER BY dr.day DESC;

COMMENT ON VIEW life.v_domain_coverage_matrix IS
'Boolean matrix showing which domains have data for each day in the last 90 days';


-- Create summary view for last 30 days coverage percentage per domain
CREATE OR REPLACE VIEW life.v_coverage_summary_30d AS
WITH coverage_matrix AS (
    SELECT * FROM life.v_domain_coverage_matrix
    WHERE day >= CURRENT_DATE - INTERVAL '30 days'
)
SELECT
    'finance_transactions' as domain,
    COUNT(*) FILTER (WHERE finance_transactions) as days_with_data,
    COUNT(*) as total_days,
    ROUND(100.0 * COUNT(*) FILTER (WHERE finance_transactions) / COUNT(*), 1) as coverage_pct
FROM coverage_matrix
UNION ALL
SELECT 'finance_receipts', COUNT(*) FILTER (WHERE finance_receipts), COUNT(*),
       ROUND(100.0 * COUNT(*) FILTER (WHERE finance_receipts) / COUNT(*), 1)
FROM coverage_matrix
UNION ALL
SELECT 'health_whoop', COUNT(*) FILTER (WHERE health_whoop), COUNT(*),
       ROUND(100.0 * COUNT(*) FILTER (WHERE health_whoop) / COUNT(*), 1)
FROM coverage_matrix
UNION ALL
SELECT 'health_body_metrics', COUNT(*) FILTER (WHERE health_body_metrics), COUNT(*),
       ROUND(100.0 * COUNT(*) FILTER (WHERE health_body_metrics) / COUNT(*), 1)
FROM coverage_matrix
UNION ALL
SELECT 'nutrition_food', COUNT(*) FILTER (WHERE nutrition_food), COUNT(*),
       ROUND(100.0 * COUNT(*) FILTER (WHERE nutrition_food) / COUNT(*), 1)
FROM coverage_matrix
UNION ALL
SELECT 'nutrition_water', COUNT(*) FILTER (WHERE nutrition_water), COUNT(*),
       ROUND(100.0 * COUNT(*) FILTER (WHERE nutrition_water) / COUNT(*), 1)
FROM coverage_matrix
UNION ALL
SELECT 'behavioral_location', COUNT(*) FILTER (WHERE behavioral_location), COUNT(*),
       ROUND(100.0 * COUNT(*) FILTER (WHERE behavioral_location) / COUNT(*), 1)
FROM coverage_matrix
UNION ALL
SELECT 'behavioral_events', COUNT(*) FILTER (WHERE behavioral_events), COUNT(*),
       ROUND(100.0 * COUNT(*) FILTER (WHERE behavioral_events) / COUNT(*), 1)
FROM coverage_matrix
UNION ALL
SELECT 'productivity_github', COUNT(*) FILTER (WHERE productivity_github), COUNT(*),
       ROUND(100.0 * COUNT(*) FILTER (WHERE productivity_github) / COUNT(*), 1)
FROM coverage_matrix
UNION ALL
SELECT 'productivity_calendar', COUNT(*) FILTER (WHERE productivity_calendar), COUNT(*),
       ROUND(100.0 * COUNT(*) FILTER (WHERE productivity_calendar) / COUNT(*), 1)
FROM coverage_matrix
UNION ALL
SELECT 'aggregated_daily_facts', COUNT(*) FILTER (WHERE aggregated_daily_facts), COUNT(*),
       ROUND(100.0 * COUNT(*) FILTER (WHERE aggregated_daily_facts) / COUNT(*), 1)
FROM coverage_matrix
ORDER BY coverage_pct DESC;

COMMENT ON VIEW life.v_coverage_summary_30d IS
'Coverage percentage by domain for the last 30 days';
