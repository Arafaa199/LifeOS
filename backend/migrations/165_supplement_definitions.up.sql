-- Migration 165: Supplement/Medication Definitions
-- Adds a table to define supplements and medications that can be tracked manually

-- Supplement definitions (what you take regularly)
CREATE TABLE IF NOT EXISTS health.supplement_definitions (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,
    brand           TEXT,
    dose_amount     NUMERIC(10,2),
    dose_unit       TEXT,                       -- mg, mcg, IU, g, ml, capsule, tablet
    frequency       TEXT NOT NULL DEFAULT 'daily',  -- daily, twice_daily, weekly, as_needed
    times_of_day    TEXT[] DEFAULT ARRAY['morning'],  -- morning, afternoon, evening, night, with_meals
    category        TEXT DEFAULT 'supplement',  -- supplement, vitamin, mineral, medication, probiotic
    notes           TEXT,
    active          BOOLEAN DEFAULT TRUE,
    start_date      DATE DEFAULT CURRENT_DATE,
    end_date        DATE,                       -- NULL = ongoing
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT supplement_frequency_check CHECK (
        frequency IN ('daily', 'twice_daily', 'three_times_daily', 'weekly', 'as_needed', 'custom')
    ),
    CONSTRAINT supplement_category_check CHECK (
        category IN ('supplement', 'vitamin', 'mineral', 'medication', 'probiotic', 'herb', 'other')
    )
);

CREATE INDEX idx_supplement_defs_active ON health.supplement_definitions (active) WHERE active = TRUE;
CREATE INDEX idx_supplement_defs_category ON health.supplement_definitions (category);

-- Trigger for updated_at
CREATE OR REPLACE FUNCTION health.update_supplement_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_supplement_defs_updated
    BEFORE UPDATE ON health.supplement_definitions
    FOR EACH ROW
    EXECUTE FUNCTION health.update_supplement_timestamp();

-- Add supplement_id foreign key to medications table
ALTER TABLE health.medications
ADD COLUMN IF NOT EXISTS supplement_id INTEGER REFERENCES health.supplement_definitions(id);

-- View to get today's expected doses based on definitions
CREATE OR REPLACE VIEW health.v_todays_supplements AS
WITH today AS (
    SELECT (NOW() AT TIME ZONE 'Asia/Dubai')::date AS d
)
SELECT
    sd.id AS supplement_id,
    sd.name,
    sd.brand,
    sd.dose_amount,
    sd.dose_unit,
    sd.frequency,
    sd.times_of_day,
    sd.category,
    unnest(sd.times_of_day) AS time_slot,
    CASE
        WHEN EXISTS (
            SELECT 1 FROM health.medications m, today
            WHERE m.supplement_id = sd.id
              AND m.scheduled_date = today.d
              AND m.status = 'taken'
        ) THEN 'taken'
        WHEN EXISTS (
            SELECT 1 FROM health.medications m, today
            WHERE m.supplement_id = sd.id
              AND m.scheduled_date = today.d
              AND m.status = 'skipped'
        ) THEN 'skipped'
        ELSE 'pending'
    END AS status
FROM health.supplement_definitions sd
WHERE sd.active = TRUE
  AND (sd.end_date IS NULL OR sd.end_date >= (NOW() AT TIME ZONE 'Asia/Dubai')::date)
  AND sd.start_date <= (NOW() AT TIME ZONE 'Asia/Dubai')::date;

-- Function to log a supplement dose
CREATE OR REPLACE FUNCTION health.log_supplement_dose(
    p_supplement_id INTEGER,
    p_status TEXT DEFAULT 'taken',
    p_time_slot TEXT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    v_supplement RECORD;
    v_today DATE;
    v_med_id INTEGER;
BEGIN
    v_today := (NOW() AT TIME ZONE 'Asia/Dubai')::date;

    -- Get supplement definition
    SELECT * INTO v_supplement
    FROM health.supplement_definitions
    WHERE id = p_supplement_id AND active = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Supplement not found or not active: %', p_supplement_id;
    END IF;

    -- Insert or update medication record
    INSERT INTO health.medications (
        medication_id,
        medication_name,
        dose_quantity,
        dose_unit,
        scheduled_date,
        scheduled_time,
        taken_at,
        status,
        source,
        supplement_id
    ) VALUES (
        'supp_' || p_supplement_id || '_' || v_today,
        v_supplement.name,
        v_supplement.dose_amount,
        v_supplement.dose_unit,
        v_today,
        CASE p_time_slot
            WHEN 'morning' THEN '08:00'
            WHEN 'afternoon' THEN '13:00'
            WHEN 'evening' THEN '18:00'
            WHEN 'night' THEN '21:00'
            WHEN 'with_meals' THEN '12:00'
            ELSE NULL
        END::time,
        CASE WHEN p_status = 'taken' THEN NOW() ELSE NULL END,
        p_status,
        'manual',
        p_supplement_id
    )
    ON CONFLICT (medication_id, scheduled_date, scheduled_time, source) DO UPDATE SET
        status = EXCLUDED.status,
        taken_at = EXCLUDED.taken_at,
        synced_at = NOW()
    RETURNING id INTO v_med_id;

    RETURN v_med_id;
END;
$$ LANGUAGE plpgsql;

-- Update the medications feed status source
INSERT INTO life.feed_status_live (source, last_event_at, events_today, expected_interval)
VALUES ('supplements', NULL, 0, INTERVAL '24 hours')
ON CONFLICT (source) DO NOTHING;

-- Grants
GRANT SELECT, INSERT, UPDATE, DELETE ON health.supplement_definitions TO nexus;
GRANT USAGE, SELECT ON SEQUENCE health.supplement_definitions_id_seq TO nexus;
GRANT EXECUTE ON FUNCTION health.log_supplement_dose(INTEGER, TEXT, TEXT, TEXT) TO nexus;

COMMENT ON TABLE health.supplement_definitions IS 'User-defined supplements and medications for daily tracking';
COMMENT ON FUNCTION health.log_supplement_dose IS 'Log a supplement dose as taken or skipped';
