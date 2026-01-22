-- Migration 016: Cleanup stale pending events
-- Marks raw_events stuck in 'pending' status as 'failed' after 5 minutes

-- Cleanup function
CREATE OR REPLACE FUNCTION finance.cleanup_stale_pending_events()
RETURNS INTEGER AS $$
DECLARE
  updated_count INTEGER;
BEGIN
  UPDATE finance.raw_events
  SET validation_status = 'failed',
      validation_errors = ARRAY['workflow_timeout']
  WHERE validation_status = 'pending'
    AND created_at < NOW() - INTERVAL '5 minutes';

  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RETURN updated_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION finance.cleanup_stale_pending_events() IS
  'Marks events stuck in pending status for >5 minutes as failed. Run hourly via n8n or cron.';

-- Manual execution example:
-- SELECT finance.cleanup_stale_pending_events();
