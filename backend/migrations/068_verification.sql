-- Verification queries for migration 068 (Calendar Schema)

-- 1. Verify table structure
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'raw' AND table_name = 'calendar_events'
ORDER BY ordinal_position;

-- 2. Verify unique constraint exists
SELECT constraint_name, constraint_type
FROM information_schema.table_constraints
WHERE table_schema = 'raw' AND table_name = 'calendar_events'
  AND constraint_type = 'UNIQUE';

-- 3. Verify indexes exist
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'calendar_events' AND schemaname = 'raw';

-- 4. Verify view exists and returns empty result
SELECT * FROM life.v_daily_calendar_summary;

-- 5. Test idempotency with sample data
-- Insert test event (with proper UUID)
INSERT INTO raw.calendar_events (event_id, title, start_at, end_at, is_all_day, calendar_name, source, client_id)
VALUES
    ('TEST-EVENT-001', 'Test Meeting', '2026-01-26 09:00:00+04', '2026-01-26 10:00:00+04', false, 'Work', 'test', '550e8400-e29b-41d4-a716-446655440000'::UUID),
    ('TEST-EVENT-002', 'All Day Event', '2026-01-26 00:00:00+04', '2026-01-26 23:59:59+04', true, 'Personal', 'test', '550e8400-e29b-41d4-a716-446655440000'::UUID);

-- Try to insert duplicate (should fail gracefully)
INSERT INTO raw.calendar_events (event_id, title, start_at, end_at, is_all_day, calendar_name, source)
VALUES ('TEST-EVENT-001', 'Duplicate Meeting', '2026-01-26 09:00:00+04', '2026-01-26 10:00:00+04', false, 'Work', 'test')
ON CONFLICT (event_id, source) DO NOTHING;

-- 6. Verify view aggregates correctly
SELECT * FROM life.v_daily_calendar_summary WHERE day = '2026-01-26';

-- 7. Cleanup test data
DELETE FROM raw.calendar_events WHERE source = 'test';

-- 8. Verify empty state again
SELECT COUNT(*) as event_count FROM raw.calendar_events;
SELECT COUNT(*) as summary_rows FROM life.v_daily_calendar_summary;
