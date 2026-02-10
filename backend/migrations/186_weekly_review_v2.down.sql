BEGIN;

-- Remove added columns (keep original columns intact)
ALTER TABLE insights.weekly_reports
    DROP COLUMN IF EXISTS score,
    DROP COLUMN IF EXISTS bjj_sessions,
    DROP COLUMN IF EXISTS bjj_streak,
    DROP COLUMN IF EXISTS avg_calories,
    DROP COLUMN IF EXISTS avg_protein,
    DROP COLUMN IF EXISTS water_days,
    DROP COLUMN IF EXISTS fasting_days,
    DROP COLUMN IF EXISTS avg_work_hours,
    DROP COLUMN IF EXISTS habit_completion_pct,
    DROP COLUMN IF EXISTS summary_text;

-- Note: dashboard.get_payload and insights.generate_weekly_report are replaced in-place.
-- To fully rollback, the previous migration's version would need to be restored.
-- The latest_weekly_review key will return NULL if no reports have scores.

DELETE FROM ops.schema_migrations WHERE filename = '186_weekly_review_v2.up.sql';

COMMIT;
