-- Migration 170 Down: Remove dead letter queue

BEGIN;

DROP VIEW IF EXISTS ops.v_dlq_summary;
DROP FUNCTION IF EXISTS ops.cleanup_dead_letters(INT);
DROP FUNCTION IF EXISTS ops.process_dead_letter_retries(INT);
DROP FUNCTION IF EXISTS ops.enqueue_dead_letter(TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, TEXT, INT);
DROP TABLE IF EXISTS ops.dead_letter_queue;

COMMIT;
