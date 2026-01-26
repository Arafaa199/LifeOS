-- Verification queries for Migration 073: Continuity Verification

-- 1. View exists
SELECT EXISTS (
    SELECT 1 FROM information_schema.views
    WHERE table_schema = 'life' AND table_name = 'v_continuity_check'
) as view_exists;

-- 2. Last 7 days coverage
SELECT * FROM life.v_continuity_check ORDER BY day DESC;

-- 3. Status summary
SELECT
    status,
    COUNT(*) as day_count
FROM life.v_continuity_check
GROUP BY status
ORDER BY day_count DESC;

-- 4. HealthKit coverage percentage
SELECT
    COUNT(*) FILTER (WHERE has_healthkit_data) as days_with_healthkit,
    COUNT(*) as total_days,
    ROUND(100.0 * COUNT(*) FILTER (WHERE has_healthkit_data) / COUNT(*), 1) as healthkit_coverage_pct
FROM life.v_continuity_check;

-- 5. Inferred meal coverage percentage
SELECT
    COUNT(*) FILTER (WHERE has_inferred_meals) as days_with_inferred_meals,
    COUNT(*) as total_days,
    ROUND(100.0 * COUNT(*) FILTER (WHERE has_inferred_meals) / COUNT(*), 1) as inferred_meal_coverage_pct
FROM life.v_continuity_check;

-- 6. Orphan meals detection
SELECT
    day,
    orphan_pending_meals
FROM life.v_continuity_check
WHERE orphan_pending_meals > 0
ORDER BY day DESC;

-- 7. All checks pass?
SELECT
    COUNT(*) FILTER (WHERE status = 'ok') as ok_days,
    COUNT(*) FILTER (WHERE status = 'orphans_detected') as orphan_days,
    COUNT(*) FILTER (WHERE status = 'missing_healthkit') as missing_healthkit_days,
    COUNT(*) FILTER (WHERE status = 'missing_inferred_meals') as missing_inferred_meals_days,
    COUNT(*) FILTER (WHERE status = 'pending') as pending_days,
    COUNT(*) as total_days
FROM life.v_continuity_check;
