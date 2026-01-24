-- Migration: 025_calorie_balance
-- Adds calorie balance view for tracking energy deficit/surplus
-- TASK-059: Calorie Balance View

-- ============================================================================
-- facts.daily_calorie_balance - Energy balance tracking
-- ============================================================================

CREATE OR REPLACE VIEW facts.daily_calorie_balance AS
SELECT
    day AS date,
    COALESCE(calories_active, 0) AS burned,
    COALESCE(calories_consumed, 0) AS consumed,
    COALESCE(calories_active, 0) - COALESCE(calories_consumed, 0) AS net,
    CASE
        WHEN calories_active IS NULL AND calories_consumed IS NULL THEN 'no_data'
        WHEN calories_active > COALESCE(calories_consumed, 0) THEN 'deficit'
        WHEN calories_active < COALESCE(calories_consumed, 0) THEN 'surplus'
        ELSE 'maintenance'
    END AS status,
    -- Additional context
    CASE
        WHEN calories_active > 0 AND calories_consumed > 0 THEN
            ROUND((calories_consumed::numeric / calories_active) * 100, 1)
        ELSE NULL
    END AS consumption_vs_burn_pct,
    data_completeness
FROM life.daily_facts
WHERE day >= NOW() - INTERVAL '90 days'
ORDER BY day DESC;

-- ============================================================================
-- facts.weekly_calorie_balance - Weekly aggregated energy balance
-- ============================================================================

CREATE OR REPLACE VIEW facts.weekly_calorie_balance AS
SELECT
    DATE_TRUNC('week', day)::date AS week_start,
    ROUND(AVG(calories_active), 0) AS avg_burned,
    ROUND(AVG(calories_consumed), 0) AS avg_consumed,
    ROUND(AVG(COALESCE(calories_active, 0) - COALESCE(calories_consumed, 0)), 0) AS avg_net,
    COUNT(*) FILTER (WHERE calories_active > COALESCE(calories_consumed, 0)) AS deficit_days,
    COUNT(*) FILTER (WHERE calories_active < COALESCE(calories_consumed, 0)) AS surplus_days,
    CASE
        WHEN AVG(COALESCE(calories_active, 0) - COALESCE(calories_consumed, 0)) > 300 THEN 'strong_deficit'
        WHEN AVG(COALESCE(calories_active, 0) - COALESCE(calories_consumed, 0)) > 0 THEN 'deficit'
        WHEN AVG(COALESCE(calories_active, 0) - COALESCE(calories_consumed, 0)) > -300 THEN 'maintenance'
        ELSE 'surplus'
    END AS weekly_status
FROM life.daily_facts
WHERE day >= NOW() - INTERVAL '12 weeks'
GROUP BY DATE_TRUNC('week', day)
ORDER BY week_start DESC;

-- Grant permissions
GRANT SELECT ON facts.daily_calorie_balance TO nexus;
GRANT SELECT ON facts.weekly_calorie_balance TO nexus;

COMMENT ON VIEW facts.daily_calorie_balance IS 'Daily energy balance - burned vs consumed calories with deficit/surplus status';
COMMENT ON VIEW facts.weekly_calorie_balance IS 'Weekly aggregated energy balance metrics';
