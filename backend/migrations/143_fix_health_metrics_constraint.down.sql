-- Migration 143 DOWN: Revert health.metrics constraint
-- Note: This just removes the constraint we added; doesn't restore old incorrect one

BEGIN;

ALTER TABLE health.metrics
DROP CONSTRAINT IF EXISTS health_metrics_date_source_type_key;

COMMIT;
