-- Down migration 110: Revert calendar + productivity correlation views

BEGIN;

DROP FUNCTION IF EXISTS insights.calendar_pattern_summary();
DROP VIEW IF EXISTS insights.calendar_productivity_correlation CASCADE;

-- Restore original meetings_hrv_correlation (NULL meeting data)
DROP VIEW IF EXISTS insights.meetings_hrv_correlation CASCADE;
CREATE VIEW insights.meetings_hrv_correlation AS
SELECT
    day,
    NULL::integer AS meeting_count,
    NULL::numeric AS meeting_hours,
    hrv,
    LEAD(hrv) OVER (ORDER BY day) AS next_day_hrv,
    recovery_score,
    LEAD(recovery_score) OVER (ORDER BY day) AS next_day_recovery
FROM life.daily_facts lf
WHERE day >= (now() - '90 days'::interval)
ORDER BY day DESC;

COMMIT;
