BEGIN;

-- TASK-PLAN.1: Add feed status trigger for habits domain
-- Problem: life.habit_completions has no AFTER INSERT trigger updating life.feed_status_live.
-- The habits domain (migration 187) is fully functional with dashboard integration but
-- invisible to Pipeline Health monitoring. When habit completions stop flowing, the system
-- can't detect the gap.
-- Fix: Insert feed entry + trigger on life.habit_completions (same pattern as migration 181).

-- 1. Insert habits source into feed_status_live (24h interval — daily habits)
INSERT INTO life.feed_status_live (source, expected_interval, events_today)
VALUES ('habits', '24 hours'::interval, 0)
ON CONFLICT (source) DO NOTHING;

-- 2. Create feed status trigger function for habits
CREATE OR REPLACE FUNCTION life.update_feed_status_habits()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO life.feed_status_live (source, last_event_at, events_today, expected_interval)
    VALUES ('habits', now(), 1, '24 hours'::interval)
    ON CONFLICT (source) DO UPDATE SET
        last_event_at = now(),
        events_today = life.feed_status_live.events_today + 1;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Create trigger on life.habit_completions (INSERT OR UPDATE — app may upsert)
CREATE TRIGGER trg_habit_completions_feed_status
    AFTER INSERT OR UPDATE ON life.habit_completions
    FOR EACH ROW
    EXECUTE FUNCTION life.update_feed_status_habits();

-- Track migration
INSERT INTO ops.schema_migrations (filename)
VALUES ('192_habits_feed_status.up.sql')
ON CONFLICT (filename) DO NOTHING;

COMMIT;
