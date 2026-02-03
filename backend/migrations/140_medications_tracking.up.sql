-- Migration 140: Medications Tracking
-- Track medication/supplement adherence from HealthKit (iOS 18+ HKMedicationDoseEvent)
--
-- Data flow: iOS HealthKit → batch webhook → health.medications → dashboard payload

BEGIN;

-- =============================================================================
-- 1. MEDICATIONS TABLE
-- =============================================================================

CREATE TABLE IF NOT EXISTS health.medications (
    id SERIAL PRIMARY KEY,
    -- HealthKit identifiers
    medication_id TEXT NOT NULL,           -- HKMedicationDoseEvent.medication.identifier
    dose_event_id TEXT,                    -- HKMedicationDoseEvent.uuid (unique per dose)

    -- Medication info
    medication_name TEXT NOT NULL,         -- Display name from HKUserAnnotatedMedication
    dose_quantity NUMERIC(10,3),           -- Amount taken (may be 0 if skipped)
    dose_unit TEXT,                        -- Unit string (e.g., "mg", "tablets")

    -- Timing
    scheduled_date DATE NOT NULL,          -- Scheduled dose date
    scheduled_time TIME,                   -- Scheduled dose time (if set)
    taken_at TIMESTAMPTZ,                  -- Actual time taken (NULL if skipped/missed)

    -- Status
    status TEXT NOT NULL DEFAULT 'scheduled',  -- scheduled, taken, skipped, missed

    -- Sync metadata
    source TEXT DEFAULT 'healthkit',
    synced_at TIMESTAMPTZ DEFAULT NOW(),

    -- Idempotency: one dose event per medication per scheduled time per source
    UNIQUE(medication_id, scheduled_date, scheduled_time, source)
);

COMMENT ON TABLE health.medications IS 'Medication/supplement dose events from HealthKit (iOS 18+)';
COMMENT ON COLUMN health.medications.status IS 'scheduled=pending, taken=confirmed, skipped=user declined, missed=past scheduled time with no action';

-- Index for daily dashboard queries
CREATE INDEX IF NOT EXISTS idx_medications_scheduled_date
ON health.medications(scheduled_date);

-- Index for medication name lookups
CREATE INDEX IF NOT EXISTS idx_medications_name
ON health.medications(medication_name);

-- =============================================================================
-- 2. DAILY MEDICATIONS VIEW
-- =============================================================================

CREATE OR REPLACE VIEW health.v_daily_medications AS
SELECT
    scheduled_date AS day,
    COUNT(*) FILTER (WHERE status IN ('scheduled', 'taken', 'skipped', 'missed')) AS doses_scheduled,
    COUNT(*) FILTER (WHERE status = 'taken') AS doses_taken,
    COUNT(*) FILTER (WHERE status = 'skipped') AS doses_skipped,
    COUNT(*) FILTER (WHERE status = 'missed') AS doses_missed,
    COUNT(DISTINCT medication_name) AS unique_medications,
    CASE
        WHEN COUNT(*) FILTER (WHERE status IN ('taken', 'skipped', 'missed')) > 0
        THEN ROUND(
            COUNT(*) FILTER (WHERE status = 'taken')::numeric /
            NULLIF(COUNT(*) FILTER (WHERE status IN ('taken', 'skipped', 'missed')), 0) * 100,
            1
        )
        ELSE NULL
    END AS adherence_pct
FROM health.medications
GROUP BY scheduled_date;

COMMENT ON VIEW health.v_daily_medications IS 'Daily medication adherence summary';

-- =============================================================================
-- 3. UPDATE DASHBOARD.GET_PAYLOAD TO INCLUDE MEDICATIONS
-- =============================================================================

CREATE OR REPLACE FUNCTION dashboard.get_payload(for_date date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    the_date DATE;
    result JSONB;
    facts_row RECORD;
    finance_data JSONB;
    feed_data JSONB;
    insights_data JSONB;
    calendar_data JSONB;
    reminder_data JSONB;
    github_data JSONB;
    fasting_data JSONB;
    medications_data JSONB;
BEGIN
    the_date := COALESCE(for_date, life.dubai_today());
    SELECT * INTO facts_row FROM life.daily_facts WHERE day = the_date;

    -- Finance summary
    SELECT jsonb_build_object(
        'spend_total', COALESCE(facts_row.spend_total, 0),
        'spend_groceries', COALESCE(facts_row.spend_groceries, 0),
        'spend_restaurants', COALESCE(facts_row.spend_restaurants, 0),
        'spend_transport', COALESCE(facts_row.spend_transport, 0),
        'income_total', COALESCE(facts_row.income_total, 0),
        'transaction_count', COALESCE(facts_row.transaction_count, 0)
    ) INTO finance_data;

    -- Feed status
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'feed', source, 'status', status, 'lastSync', last_event_at,
            'hoursSinceSync', EXTRACT(EPOCH FROM (NOW() - last_event_at)) / 3600
        )
    ), '[]'::jsonb) INTO feed_data FROM life.feed_status;

    -- Insights
    SELECT COALESCE(insights.get_ranked_insights(the_date), '{}'::jsonb) INTO insights_data;

    -- Calendar
    SELECT COALESCE(
        (SELECT jsonb_build_object(
            'meeting_count', meeting_count, 'meeting_hours', meeting_hours,
            'first_meeting', first_meeting, 'last_meeting', last_meeting
        ) FROM life.v_daily_calendar_summary WHERE day = the_date),
        jsonb_build_object('meeting_count', 0, 'meeting_hours', 0, 'first_meeting', NULL, 'last_meeting', NULL)
    ) INTO calendar_data;

    -- Reminders
    SELECT jsonb_build_object(
        'due_today', COALESCE(facts_row.reminders_due, 0),
        'completed_today', COALESCE(facts_row.reminders_completed, 0),
        'overdue_count', (SELECT COUNT(*) FROM raw.reminders WHERE deleted_at IS NULL AND is_completed = false AND due_date < the_date)::int
    ) INTO reminder_data;

    -- GitHub
    SELECT COALESCE(life.get_github_activity_widget(14), '{}'::jsonb) INTO github_data;

    -- Fasting
    SELECT health.get_fasting_status() INTO fasting_data;

    -- Medications summary (NEW)
    SELECT jsonb_build_object(
        'due_today', COALESCE(SUM(CASE WHEN status IN ('scheduled', 'taken', 'skipped') THEN 1 ELSE 0 END)::int, 0),
        'taken_today', COALESCE(SUM(CASE WHEN status = 'taken' THEN 1 ELSE 0 END)::int, 0),
        'skipped_today', COALESCE(SUM(CASE WHEN status = 'skipped' THEN 1 ELSE 0 END)::int, 0),
        'adherence_pct', CASE
            WHEN COUNT(*) FILTER (WHERE status IN ('taken', 'skipped')) > 0
            THEN ROUND(
                COUNT(*) FILTER (WHERE status = 'taken')::numeric /
                NULLIF(COUNT(*) FILTER (WHERE status IN ('taken', 'skipped')), 0) * 100,
                1
            )
            ELSE NULL
        END,
        'medications', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'name', medication_name,
                'status', status,
                'scheduled_time', scheduled_time::text,
                'taken_at', taken_at
            ) ORDER BY scheduled_time NULLS LAST)
            FROM health.medications
            WHERE scheduled_date = the_date
        ), '[]'::jsonb)
    )
    INTO medications_data
    FROM health.medications
    WHERE scheduled_date = the_date;

    -- Default if no medication data
    IF medications_data IS NULL OR medications_data->>'due_today' IS NULL THEN
        medications_data := jsonb_build_object(
            'due_today', 0,
            'taken_today', 0,
            'skipped_today', 0,
            'adherence_pct', NULL,
            'medications', '[]'::jsonb
        );
    END IF;

    -- Build final result (schema_version 9 → 10)
    result := jsonb_build_object(
        'schema_version', 10, 'generated_at', NOW(), 'target_date', the_date,
        'today_facts', jsonb_build_object(
            'day', the_date, 'recovery_score', facts_row.recovery_score, 'hrv', facts_row.hrv,
            'rhr', facts_row.rhr, 'sleep_minutes', facts_row.sleep_minutes,
            'sleep_hours', facts_row.sleep_hours, 'deep_sleep_hours', facts_row.deep_sleep_hours,
            'sleep_efficiency', facts_row.sleep_efficiency, 'strain', facts_row.strain,
            'weight_kg', facts_row.weight_kg, 'spend_total', facts_row.spend_total,
            'spend_vs_7d', ROUND(((facts_row.spend_total - (SELECT AVG(spend_total) FROM life.daily_facts WHERE day BETWEEN the_date - 7 AND the_date - 1)) / NULLIF((SELECT AVG(spend_total) FROM life.daily_facts WHERE day BETWEEN the_date - 7 AND the_date - 1), 0) * 100)::numeric, 1),
            'spend_unusual', facts_row.spend_total > COALESCE((SELECT AVG(spend_total) + 2 * STDDEV(spend_total) FROM life.daily_facts WHERE day BETWEEN the_date - 30 AND the_date - 1), 9999),
            'meals_logged', COALESCE(facts_row.meals_logged, 0), 'water_ml', COALESCE(facts_row.water_ml, 0),
            'calories_consumed', facts_row.calories_consumed, 'protein_g', facts_row.protein_g,
            'data_completeness', facts_row.data_completeness
        ),
        'finance_summary', finance_data, 'feed_status', feed_data,
        'stale_feeds', (SELECT COALESCE(array_agg(source), '{}') FROM life.feed_status WHERE status IN ('stale', 'error')),
        'daily_insights', insights_data, 'calendar_summary', calendar_data,
        'reminder_summary', reminder_data, 'github_activity', github_data,
        'fasting', fasting_data,
        'medications_today', medications_data
    );

    RETURN result;
END;
$function$;

-- =============================================================================
-- 4. ADD FEED STATUS ENTRY FOR MEDICATIONS
-- =============================================================================

INSERT INTO life.feed_status_live (source, last_event_at, events_today, expected_interval)
VALUES ('medications', NULL, 0, INTERVAL '48 hours')
ON CONFLICT (source) DO NOTHING;

-- =============================================================================
-- 5. FEED STATUS TRIGGER FOR MEDICATIONS
-- =============================================================================

CREATE OR REPLACE FUNCTION health.update_medications_feed_status()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE life.feed_status_live
    SET last_event_at = NOW(),
        events_today = events_today + 1
    WHERE source = 'medications';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_medications_feed_status ON health.medications;
CREATE TRIGGER trg_medications_feed_status
    AFTER INSERT ON health.medications
    FOR EACH ROW
    EXECUTE FUNCTION health.update_medications_feed_status();

COMMIT;
