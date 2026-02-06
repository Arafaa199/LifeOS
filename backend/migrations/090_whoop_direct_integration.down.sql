-- Rollback: 090_whoop_direct_integration
-- This migration updates WHOOP propagation triggers and dashboard.get_payload().

-- Drop new triggers (safe)
DROP TRIGGER IF EXISTS trg_feed_whoop_sleep ON health.whoop_sleep;
DROP TRIGGER IF EXISTS trg_feed_whoop_strain ON health.whoop_strain;
DROP FUNCTION IF EXISTS life.update_feed_status_sleep();
DROP FUNCTION IF EXISTS life.update_feed_status_strain();

-- Note: Propagation functions and get_payload() not reverted - would need previous versions
SELECT 'Migration 090 partially rolled back - triggers dropped, functions not reverted';
