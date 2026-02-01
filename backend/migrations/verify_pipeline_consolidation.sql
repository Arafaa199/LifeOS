-- =============================================================================
-- Verification SQL: Pipeline Consolidation (Migrations 119-123)
-- Run AFTER applying all migrations and calling:
--   SELECT * FROM life.rebuild_daily_facts('2025-01-01', life.dubai_today());
--
-- Every query below should return ZERO rows if the pipeline is correct.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Finance: normalized view vs legacy direct query
--    Compares normalized.v_daily_finance against direct finance.transactions
-- ---------------------------------------------------------------------------
WITH legacy AS (
    SELECT
        finance.to_business_date(transaction_at) AS date,
        COALESCE(SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END), 0) AS spend_total,
        COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0) AS income_total,
        COUNT(*)::INT AS transaction_count
    FROM finance.transactions
    WHERE is_quarantined IS NOT TRUE
    GROUP BY finance.to_business_date(transaction_at)
),
normalized AS (
    SELECT date, spend_total, income_total, transaction_count
    FROM normalized.v_daily_finance
)
SELECT
    COALESCE(l.date, n.date) AS date,
    l.spend_total AS legacy_spend, n.spend_total AS norm_spend,
    l.income_total AS legacy_income, n.income_total AS norm_income,
    l.transaction_count AS legacy_count, n.transaction_count AS norm_count
FROM legacy l
FULL OUTER JOIN normalized n ON l.date = n.date
WHERE l.spend_total IS DISTINCT FROM n.spend_total
   OR l.income_total IS DISTINCT FROM n.income_total
   OR l.transaction_count IS DISTINCT FROM n.transaction_count;

-- ---------------------------------------------------------------------------
-- 2. Health Recovery: normalized vs legacy
-- ---------------------------------------------------------------------------
SELECT
    wr.date,
    wr.recovery_score AS legacy_score, nr.recovery_score AS norm_score,
    wr.hrv_rmssd AS legacy_hrv, nr.hrv AS norm_hrv,
    wr.rhr AS legacy_rhr, nr.rhr AS norm_rhr
FROM health.whoop_recovery wr
FULL OUTER JOIN normalized.daily_recovery nr ON wr.date = nr.date
WHERE wr.recovery_score IS DISTINCT FROM nr.recovery_score
   OR wr.hrv_rmssd IS DISTINCT FROM nr.hrv
   OR wr.rhr IS DISTINCT FROM nr.rhr;

-- ---------------------------------------------------------------------------
-- 3. Health Sleep: normalized vs legacy
-- ---------------------------------------------------------------------------
SELECT
    ws.date,
    ws.time_in_bed_min AS legacy_tib, ns.time_in_bed_min AS norm_tib,
    ws.deep_sleep_min AS legacy_deep, ns.deep_sleep_min AS norm_deep,
    ws.rem_sleep_min AS legacy_rem, ns.rem_sleep_min AS norm_rem,
    ws.sleep_efficiency AS legacy_eff, ns.sleep_efficiency AS norm_eff
FROM health.whoop_sleep ws
FULL OUTER JOIN normalized.daily_sleep ns ON ws.date = ns.date
WHERE ws.time_in_bed_min IS DISTINCT FROM ns.time_in_bed_min
   OR ws.deep_sleep_min IS DISTINCT FROM ns.deep_sleep_min
   OR ws.rem_sleep_min IS DISTINCT FROM ns.rem_sleep_min
   OR ws.sleep_efficiency IS DISTINCT FROM ns.sleep_efficiency;

-- ---------------------------------------------------------------------------
-- 4. Health Strain: normalized vs legacy (including calories_active)
-- ---------------------------------------------------------------------------
SELECT
    wst.date,
    wst.day_strain AS legacy_strain, nst.day_strain AS norm_strain,
    wst.calories_active AS legacy_cal_active, nst.calories_active AS norm_cal_active,
    wst.calories_total AS legacy_cal_total, nst.calories_burned AS norm_cal_burned
FROM health.whoop_strain wst
FULL OUTER JOIN normalized.daily_strain nst ON wst.date = nst.date
WHERE wst.day_strain IS DISTINCT FROM nst.day_strain
   OR wst.calories_active IS DISTINCT FROM nst.calories_active
   OR wst.calories_total IS DISTINCT FROM nst.calories_burned;

-- ---------------------------------------------------------------------------
-- 5. daily_facts completeness: no NULL days in expected range
--    Returns days that exist in normalized sources but are missing from daily_facts
-- ---------------------------------------------------------------------------
WITH expected_days AS (
    SELECT date FROM normalized.daily_recovery
    UNION
    SELECT date FROM normalized.daily_sleep
    UNION
    SELECT date FROM normalized.daily_strain
    UNION
    SELECT date FROM normalized.v_daily_finance
)
SELECT ed.date AS missing_day
FROM expected_days ed
LEFT JOIN life.daily_facts df ON df.day = ed.date
WHERE df.day IS NULL
  AND ed.date >= '2025-01-01'
ORDER BY ed.date;

-- ---------------------------------------------------------------------------
-- 6. Rebuild audit: verify last rebuild had zero failures
-- ---------------------------------------------------------------------------
SELECT id, run_id, start_date, end_date, days_requested, days_succeeded, days_failed, errors
FROM ops.rebuild_runs
ORDER BY started_at DESC
LIMIT 1;

-- ---------------------------------------------------------------------------
-- 7. Silent trigger failures: check ops.trigger_errors for recent issues
-- ---------------------------------------------------------------------------
SELECT trigger_name, table_name, error_message, created_at
FROM ops.trigger_errors
WHERE created_at > NOW() - INTERVAL '7 days'
ORDER BY created_at DESC;

-- ---------------------------------------------------------------------------
-- 8. Deprecation check: facts.* tables should be stale (not refreshed recently)
--    After migration 122, these should stop getting new writes.
-- ---------------------------------------------------------------------------
SELECT 'facts.daily_health' AS table_name, MAX(refreshed_at) AS last_refresh FROM facts.daily_health
UNION ALL
SELECT 'facts.daily_finance', MAX(refreshed_at) FROM facts.daily_finance
UNION ALL
SELECT 'facts.daily_nutrition', MAX(refreshed_at) FROM facts.daily_nutrition;
