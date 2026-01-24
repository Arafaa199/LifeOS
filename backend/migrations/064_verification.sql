-- Verification queries for TASK-VIS.2
-- Date: 2026-01-25

\echo '=== TASK-VIS.2 Verification ==='
\echo ''

\echo '1. Verify timeline is included in daily summary'
SELECT
    (life.get_daily_summary(CURRENT_DATE) -> 'finance' -> 'timeline') IS NOT NULL as has_timeline,
    jsonb_array_length(life.get_daily_summary(CURRENT_DATE) -> 'finance' -> 'timeline') as timeline_count;

\echo ''
\echo '2. Verify timeline event types'
SELECT
    value->>'type' as event_type,
    COUNT(*) as count
FROM jsonb_array_elements(
    (life.get_daily_summary(CURRENT_DATE) -> 'finance' -> 'timeline')
) as value
GROUP BY value->>'type'
ORDER BY count DESC;

\echo ''
\echo '3. Verify timeline sorting (most recent first)'
SELECT
    value->>'time' as time,
    value->>'type' as type,
    (value->>'amount')::NUMERIC as amount,
    value->>'merchant' as merchant
FROM jsonb_array_elements(
    (life.get_daily_summary(CURRENT_DATE) -> 'finance' -> 'timeline')
) as value
LIMIT 5;

\echo ''
\echo '4. Verify actionable flag distribution'
SELECT
    value->>'actionable' as is_actionable,
    COUNT(*) as count
FROM jsonb_array_elements(
    (life.get_daily_summary(CURRENT_DATE) -> 'finance' -> 'timeline')
) as value
GROUP BY value->>'actionable';

\echo ''
\echo '5. Verify performance (execution time)'
EXPLAIN ANALYZE
SELECT life.get_daily_summary(CURRENT_DATE);

\echo ''
\echo '6. Verify backward compatibility (all original keys exist)'
SELECT
    jsonb_object_keys(life.get_daily_summary(CURRENT_DATE) -> 'finance') as finance_keys
ORDER BY finance_keys;

\echo ''
\echo '7. Verify timeline for day with no transactions'
SELECT
    (life.get_daily_summary('2026-01-01') -> 'finance' -> 'timeline') as timeline_empty_day,
    jsonb_array_length(COALESCE(life.get_daily_summary('2026-01-01') -> 'finance' -> 'timeline', '[]'::jsonb)) as count;

\echo ''
\echo '=== Verification Complete ==='
