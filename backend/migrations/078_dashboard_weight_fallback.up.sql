-- Migration: 078_dashboard_weight_fallback
-- Purpose: Fix dashboard to show latest weight when no weight logged today
-- Issue: Weight was showing as null if not logged today, even though recent data exists

BEGIN;

CREATE OR REPLACE VIEW dashboard.v_today AS
SELECT
    1 AS schema_version,
    now() AS generated_at,
    life.dubai_today() AS for_date,
    f.day,
    f.recovery_score,
    f.hrv,
    f.rhr,
    f.sleep_minutes,
    f.deep_sleep_minutes,
    f.rem_sleep_minutes,
    f.sleep_efficiency,
    f.strain,
    f.steps,
    -- Use today's weight OR fall back to latest known weight
    COALESCE(f.weight_kg, (
        SELECT weight_kg FROM life.daily_facts
        WHERE weight_kg IS NOT NULL
        ORDER BY day DESC LIMIT 1
    )) AS weight_kg,
    f.spend_total,
    f.spend_groceries,
    f.spend_restaurants,
    f.income_total,
    f.transaction_count,
    f.meals_logged,
    f.water_ml,
    f.calories_consumed,
    f.data_completeness,
    f.computed_at AS facts_computed_at,
    f.recovery_score::numeric - b.recovery_7d_avg AS recovery_vs_7d,
    f.recovery_score::numeric - b.recovery_30d_avg AS recovery_vs_30d,
    f.hrv - b.hrv_7d_avg AS hrv_vs_7d,
    f.sleep_minutes::numeric - b.sleep_minutes_7d_avg AS sleep_vs_7d,
    f.strain - b.strain_7d_avg AS strain_vs_7d,
    f.spend_total - b.spend_7d_avg AS spend_vs_7d,
    f.weight_kg - b.weight_7d_avg AS weight_vs_7d,
    CASE
        WHEN b.recovery_7d_stddev > 0 AND abs(f.recovery_score::numeric - b.recovery_7d_avg) > (1.5 * b.recovery_7d_stddev) THEN true
        ELSE false
    END AS recovery_unusual,
    CASE
        WHEN b.sleep_minutes_7d_stddev > 0 AND abs(f.sleep_minutes::numeric - b.sleep_minutes_7d_avg) > (1.5 * b.sleep_minutes_7d_stddev) THEN true
        ELSE false
    END AS sleep_unusual,
    CASE
        WHEN b.spend_7d_stddev > 0 AND abs(f.spend_total - b.spend_7d_avg) > (1.5 * b.spend_7d_stddev) THEN true
        ELSE false
    END AS spend_unusual,
    b.recovery_7d_avg,
    b.recovery_30d_avg,
    b.hrv_7d_avg,
    b.sleep_minutes_7d_avg,
    b.weight_30d_delta,
    b.days_with_data_7d,
    b.days_with_data_30d,
    b.computed_at AS baselines_computed_at
FROM life.daily_facts f
CROSS JOIN life.baselines b
WHERE f.day = life.dubai_today();

COMMENT ON VIEW dashboard.v_today IS 'Today facts with fallback to latest weight if not logged today';

COMMIT;
