-- Verification queries for Migration 072: Meal Inference Engine

-- 1. Verify table and view exist
SELECT
    'meal_confirmations' as object_name,
    CASE WHEN EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'life' AND table_name = 'meal_confirmations'
    ) THEN '✓ EXISTS' ELSE '✗ MISSING' END as status
UNION ALL
SELECT
    'v_inferred_meals',
    CASE WHEN EXISTS (
        SELECT 1 FROM information_schema.views
        WHERE table_schema = 'life' AND table_name = 'v_inferred_meals'
    ) THEN '✓ EXISTS' ELSE '✗ MISSING' END
UNION ALL
SELECT
    'get_pending_meal_confirmations()',
    CASE WHEN EXISTS (
        SELECT 1 FROM information_schema.routines
        WHERE routine_schema = 'life' AND routine_name = 'get_pending_meal_confirmations'
    ) THEN '✓ EXISTS' ELSE '✗ MISSING' END;

-- 2. View inferred meals for last 7 days
SELECT
    inferred_at_date,
    inferred_at_time,
    meal_type,
    confidence,
    inference_source,
    confirmation_status,
    jsonb_pretty(signals_used) as signals
FROM life.v_inferred_meals
WHERE inferred_at_date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY inferred_at_date DESC, inferred_at_time DESC
LIMIT 20;

-- 3. Meal inference summary by type and source
SELECT
    meal_type,
    inference_source,
    COUNT(*) as inference_count,
    ROUND(AVG(confidence)::NUMERIC, 2) as avg_confidence,
    MIN(inferred_at_date) as earliest_date,
    MAX(inferred_at_date) as latest_date
FROM life.v_inferred_meals
WHERE inferred_at_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY meal_type, inference_source
ORDER BY meal_type, avg_confidence DESC;

-- 4. Test get_pending_meal_confirmations function
SELECT
    meal_date,
    meal_time,
    meal_type,
    confidence,
    inference_source
FROM life.get_pending_meal_confirmations(CURRENT_DATE - INTERVAL '1 day')
ORDER BY meal_time DESC;

-- 5. Daily meal inference coverage (last 7 days)
SELECT
    gs.date as day,
    COUNT(DISTINCT CONCAT(v.inferred_at_date, v.inferred_at_time)) as meals_inferred,
    COUNT(DISTINCT v.meal_type) as meal_types_detected,
    ARRAY_AGG(DISTINCT v.meal_type ORDER BY v.meal_type) FILTER (WHERE v.meal_type IS NOT NULL) as meal_types
FROM generate_series(CURRENT_DATE - INTERVAL '7 days', CURRENT_DATE, '1 day'::interval) gs(date)
LEFT JOIN life.v_inferred_meals v ON v.inferred_at_date = gs.date::DATE
GROUP BY gs.date
ORDER BY gs.date DESC;

-- 6. Signal quality check
SELECT
    inference_source,
    COUNT(*) as total_inferences,
    COUNT(*) FILTER (WHERE confidence >= 0.8) as high_confidence,
    COUNT(*) FILTER (WHERE confidence BETWEEN 0.5 AND 0.8) as medium_confidence,
    COUNT(*) FILTER (WHERE confidence < 0.5) as low_confidence,
    ROUND(100.0 * COUNT(*) FILTER (WHERE confidence >= 0.8) / COUNT(*), 1) as high_conf_pct
FROM life.v_inferred_meals
WHERE inferred_at_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY inference_source
ORDER BY total_inferences DESC;
