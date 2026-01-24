-- Migration 016 Rollback: Remove cleanup function

DROP FUNCTION IF EXISTS finance.cleanup_stale_pending_events();
