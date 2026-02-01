-- Migration 123: Deterministic rebuild function
--
-- Provides life.rebuild_daily_facts(start_date, end_date) that:
-- 1. Deletes existing life.daily_facts rows in the range
-- 2. Re-inserts by calling life.refresh_daily_facts() per day
-- 3. Logs the rebuild to ops.rebuild_runs for audit
-- 4. Returns per-day status so you can verify completeness
--
-- This makes rebuilds deterministic: delete + recompute = provably correct.
-- Advisory-locked to prevent concurrent rebuilds.

-- =============================================================================
-- 1. Audit table for rebuild operations
-- =============================================================================

CREATE TABLE IF NOT EXISTS ops.rebuild_runs (
    id SERIAL PRIMARY KEY,
    run_id UUID NOT NULL DEFAULT gen_random_uuid(),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    days_requested INT NOT NULL,
    days_succeeded INT NOT NULL DEFAULT 0,
    days_failed INT NOT NULL DEFAULT 0,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at TIMESTAMPTZ,
    duration_ms INT,
    triggered_by VARCHAR(50) DEFAULT 'manual',
    errors JSONB DEFAULT '[]'::jsonb
);

CREATE INDEX idx_rebuild_runs_started ON ops.rebuild_runs(started_at DESC);

COMMENT ON TABLE ops.rebuild_runs IS
'Audit log for life.rebuild_daily_facts() invocations. Each row = one rebuild run.';

-- =============================================================================
-- 2. Rebuild function
-- =============================================================================

CREATE OR REPLACE FUNCTION life.rebuild_daily_facts(
    p_start DATE DEFAULT NULL,
    p_end DATE DEFAULT NULL,
    p_triggered_by TEXT DEFAULT 'manual'
)
RETURNS TABLE(day DATE, status TEXT, detail TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_start DATE;
    v_end DATE;
    v_day DATE;
    v_lock_id BIGINT := 8675309;  -- fixed lock ID for rebuild
    v_run_id UUID;
    v_log_id INT;
    v_start_ts TIMESTAMPTZ;
    v_succeeded INT := 0;
    v_failed INT := 0;
    v_errors JSONB := '[]'::jsonb;
    v_result RECORD;
BEGIN
    -- Default range: last 7 days
    v_end := COALESCE(p_end, life.dubai_today());
    v_start := COALESCE(p_start, v_end - 6);

    -- Sanity check
    IF v_start > v_end THEN
        RETURN QUERY SELECT v_start, 'error'::TEXT, 'start_date > end_date'::TEXT;
        RETURN;
    END IF;

    IF (v_end - v_start) > 365 THEN
        RETURN QUERY SELECT v_start, 'error'::TEXT, 'range exceeds 365 days'::TEXT;
        RETURN;
    END IF;

    -- Advisory lock to prevent concurrent rebuilds
    IF NOT pg_try_advisory_lock(v_lock_id) THEN
        RETURN QUERY SELECT v_start, 'skipped'::TEXT, 'concurrent rebuild in progress'::TEXT;
        RETURN;
    END IF;

    v_run_id := gen_random_uuid();
    v_start_ts := clock_timestamp();

    -- Log the rebuild start
    INSERT INTO ops.rebuild_runs (run_id, start_date, end_date, days_requested, triggered_by)
    VALUES (v_run_id, v_start, v_end, (v_end - v_start + 1), p_triggered_by)
    RETURNING id INTO v_log_id;

    -- Delete existing rows in range
    DELETE FROM life.daily_facts
    WHERE life.daily_facts.day BETWEEN v_start AND v_end;

    -- Recompute each day
    FOR v_day IN SELECT generate_series(v_start, v_end, '1 day'::interval)::date
    LOOP
        BEGIN
            SELECT * INTO v_result FROM life.refresh_daily_facts(v_day, 'rebuild_' || v_run_id::text);

            IF v_result.status = 'success' THEN
                v_succeeded := v_succeeded + 1;
                RETURN QUERY SELECT v_day, 'ok'::TEXT, format('rows=%s', v_result.rows_affected);
            ELSE
                v_failed := v_failed + 1;
                v_errors := v_errors || jsonb_build_object('day', v_day, 'status', v_result.status);
                RETURN QUERY SELECT v_day, v_result.status, ''::TEXT;
            END IF;

        EXCEPTION WHEN OTHERS THEN
            v_failed := v_failed + 1;
            v_errors := v_errors || jsonb_build_object('day', v_day, 'error', SQLERRM);
            RETURN QUERY SELECT v_day, 'error'::TEXT, SQLERRM;
        END;
    END LOOP;

    -- Finalize audit row
    UPDATE ops.rebuild_runs
    SET days_succeeded = v_succeeded,
        days_failed = v_failed,
        finished_at = clock_timestamp(),
        duration_ms = EXTRACT(EPOCH FROM (clock_timestamp() - v_start_ts)) * 1000,
        errors = v_errors
    WHERE id = v_log_id;

    PERFORM pg_advisory_unlock(v_lock_id);
    RETURN;
END;
$$;

COMMENT ON FUNCTION life.rebuild_daily_facts IS
'Deterministic rebuild: DELETE + recompute life.daily_facts for a date range. '
'Advisory-locked, audited to ops.rebuild_runs. Default range: last 7 days. '
'Migration 123.';
