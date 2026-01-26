-- Verification queries for migration 075: Coverage Truth Report

-- 1. View exists and has correct columns
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'life' AND table_name = 'v_coverage_truth'
ORDER BY ordinal_position;

-- 2. Last 30 days coverage
SELECT
    day,
    transactions_found,
    meals_found,
    inferred_meals,
    confirmed_meals,
    gap_status,
    explanation
FROM life.v_coverage_truth
ORDER BY day DESC;

-- 3. Summary statistics
SELECT
    gap_status,
    COUNT(*) as day_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) as pct
FROM life.v_coverage_truth
GROUP BY gap_status
ORDER BY day_count DESC;

-- 4. Zero unexplained gaps (gaps must have explanation)
SELECT
    COUNT(*) FILTER (WHERE gap_status = 'gap' AND explanation IS NULL) as unexplained_gaps
FROM life.v_coverage_truth;
-- Expected: 0

-- 5. All gaps are explained
SELECT
    day,
    gap_status,
    transactions_found,
    meals_found,
    explanation
FROM life.v_coverage_truth
WHERE gap_status = 'gap'
ORDER BY day DESC;
