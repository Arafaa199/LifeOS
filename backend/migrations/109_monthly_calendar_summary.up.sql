-- Migration 109: Monthly calendar summary view
-- Provides per-day event stats for month grid display
-- Powers CalendarMonthView (dots on days with events, color intensity by meeting hours)

CREATE OR REPLACE VIEW life.v_monthly_calendar_summary AS
SELECT
    (start_at AT TIME ZONE 'Asia/Dubai')::date AS day,
    COUNT(*) AS event_count,
    COUNT(*) FILTER (WHERE is_all_day = true) AS all_day_count,
    ROUND(
        SUM(EXTRACT(epoch FROM end_at - start_at) / 3600.0)
        FILTER (WHERE is_all_day = false),
        2
    ) AS meeting_hours,
    CASE WHEN COUNT(*) > 0 THEN true ELSE false END AS has_events,
    MIN(start_at AT TIME ZONE 'Asia/Dubai')::time AS first_event_time,
    MAX(start_at AT TIME ZONE 'Asia/Dubai')::time AS last_event_time
FROM raw.calendar_events
GROUP BY (start_at AT TIME ZONE 'Asia/Dubai')::date
ORDER BY day DESC;
