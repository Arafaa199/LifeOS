-- Verification queries for migration 071: Canonical Daily Summary

-- 1. Check materialized view exists and has data
SELECT COUNT(*) as row_count FROM life.mv_daily_summary;

-- 2. Check recent days (last 7)
SELECT day, recovery_score, sleep_hours, spend_total, transaction_count, tv_hours, time_at_home_minutes
FROM life.mv_daily_summary
WHERE day >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY day DESC;

-- 3. Test refresh_daily_summary function
SELECT life.refresh_daily_summary(CURRENT_DATE - INTERVAL '1 day');

-- 4. Test get_daily_summary_canonical function
SELECT jsonb_pretty(life.get_daily_summary_canonical(CURRENT_DATE - INTERVAL '1 day'));

-- 5. Compare with original daily_facts (should match)
SELECT
    'mv_daily_summary' as source,
    day,
    recovery_score,
    spend_total,
    transaction_count
FROM life.mv_daily_summary
WHERE day = CURRENT_DATE - INTERVAL '1 day'
UNION ALL
SELECT
    'daily_facts' as source,
    day,
    recovery_score,
    spend_total,
    transaction_count
FROM life.daily_facts
WHERE day = CURRENT_DATE - INTERVAL '1 day'
ORDER BY source;

-- 6. Performance test
EXPLAIN ANALYZE SELECT * FROM life.mv_daily_summary WHERE day = CURRENT_DATE - INTERVAL '1 day';

-- 7. Check indexes
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'mv_daily_summary' AND schemaname = 'life';
