-- Migration: 003_create_raw_schema
-- Purpose: Create raw.* schema for immutable source data
-- Part of Phase 1: Data Pipeline Architecture
--
-- Rules:
-- - INSERT only (no UPDATE, no DELETE)
-- - Store complete payload (JSON when applicable)
-- - Track ingestion metadata: source, ingested_at, run_id
-- - No data cleaning or transformation

BEGIN;

-- Create the raw schema
CREATE SCHEMA IF NOT EXISTS raw;

COMMENT ON SCHEMA raw IS 'Immutable source data. INSERT only, never modify after insert.';

-- =============================================================================
-- raw.whoop_cycles - Raw WHOOP cycle/recovery data from Home Assistant → n8n
-- =============================================================================
CREATE TABLE raw.whoop_cycles (
    id BIGSERIAL PRIMARY KEY,
    cycle_id BIGINT NOT NULL,              -- WHOOP's cycle ID
    date DATE NOT NULL,

    -- Exact values from source
    recovery_score INT,
    hrv DECIMAL(5,1),
    rhr INT,
    spo2 DECIMAL(4,1),
    skin_temp DECIMAL(4,1),

    -- Full payload
    raw_json JSONB NOT NULL,

    -- Ingestion metadata
    source VARCHAR(50) NOT NULL DEFAULT 'home_assistant',
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    run_id UUID NOT NULL,

    -- Natural key for dedup in normalized layer
    UNIQUE(cycle_id)
);

CREATE INDEX idx_raw_whoop_cycles_date ON raw.whoop_cycles(date DESC);
CREATE INDEX idx_raw_whoop_cycles_ingested ON raw.whoop_cycles(ingested_at DESC);

COMMENT ON TABLE raw.whoop_cycles IS 'Raw WHOOP cycle/recovery data. Immutable after insert.';
COMMENT ON COLUMN raw.whoop_cycles.cycle_id IS 'WHOOP internal cycle identifier';
COMMENT ON COLUMN raw.whoop_cycles.raw_json IS 'Complete payload from source for debugging/reprocessing';
COMMENT ON COLUMN raw.whoop_cycles.run_id IS 'UUID identifying the ingestion run for tracking';

-- =============================================================================
-- raw.whoop_sleep - Raw WHOOP sleep data
-- =============================================================================
CREATE TABLE raw.whoop_sleep (
    id BIGSERIAL PRIMARY KEY,
    sleep_id BIGINT NOT NULL,              -- WHOOP's sleep ID
    date DATE NOT NULL,                    -- Date sleep ended

    -- Exact values from source
    sleep_start TIMESTAMPTZ,
    sleep_end TIMESTAMPTZ,
    time_in_bed_ms BIGINT,
    light_sleep_ms BIGINT,
    deep_sleep_ms BIGINT,
    rem_sleep_ms BIGINT,
    awake_ms BIGINT,
    sleep_efficiency DECIMAL(5,2),
    sleep_performance INT,
    respiratory_rate DECIMAL(4,1),

    -- Full payload
    raw_json JSONB NOT NULL,

    -- Ingestion metadata
    source VARCHAR(50) NOT NULL DEFAULT 'home_assistant',
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    run_id UUID NOT NULL,

    UNIQUE(sleep_id)
);

CREATE INDEX idx_raw_whoop_sleep_date ON raw.whoop_sleep(date DESC);
CREATE INDEX idx_raw_whoop_sleep_ingested ON raw.whoop_sleep(ingested_at DESC);

COMMENT ON TABLE raw.whoop_sleep IS 'Raw WHOOP sleep data. Immutable after insert.';
COMMENT ON COLUMN raw.whoop_sleep.date IS 'Date when sleep ended (canonical day assignment)';

-- =============================================================================
-- raw.whoop_strain - Raw WHOOP strain/workout data
-- =============================================================================
CREATE TABLE raw.whoop_strain (
    id BIGSERIAL PRIMARY KEY,
    strain_id BIGINT NOT NULL,
    date DATE NOT NULL,

    day_strain DECIMAL(4,1),
    workout_count INT,
    kilojoules DECIMAL(8,1),
    average_hr INT,
    max_hr INT,

    raw_json JSONB NOT NULL,

    source VARCHAR(50) NOT NULL DEFAULT 'home_assistant',
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    run_id UUID NOT NULL,

    UNIQUE(strain_id)
);

CREATE INDEX idx_raw_whoop_strain_date ON raw.whoop_strain(date DESC);
CREATE INDEX idx_raw_whoop_strain_ingested ON raw.whoop_strain(ingested_at DESC);

COMMENT ON TABLE raw.whoop_strain IS 'Raw WHOOP strain/workout data. Immutable after insert.';

-- =============================================================================
-- raw.healthkit_samples - Raw HealthKit data from iOS app webhook
-- =============================================================================
CREATE TABLE raw.healthkit_samples (
    id BIGSERIAL PRIMARY KEY,
    sample_type VARCHAR(100) NOT NULL,     -- 'weight', 'steps', 'active_energy', etc.

    value DECIMAL(12,4) NOT NULL,
    unit VARCHAR(30) NOT NULL,

    start_date TIMESTAMPTZ NOT NULL,
    end_date TIMESTAMPTZ NOT NULL,

    -- HealthKit metadata
    device_name VARCHAR(100),
    source_name VARCHAR(100),              -- 'Eufy Scale', 'Apple Watch', etc.
    metadata JSONB,

    -- Ingestion metadata
    source VARCHAR(50) NOT NULL DEFAULT 'ios_healthkit',
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    run_id UUID NOT NULL,

    -- Dedup key: same sample from same source at same time
    UNIQUE(sample_type, source_name, start_date, end_date)
);

CREATE INDEX idx_raw_healthkit_type_date ON raw.healthkit_samples(sample_type, start_date DESC);
CREATE INDEX idx_raw_healthkit_ingested ON raw.healthkit_samples(ingested_at DESC);

COMMENT ON TABLE raw.healthkit_samples IS 'Raw HealthKit samples from iOS app. Immutable after insert.';
COMMENT ON COLUMN raw.healthkit_samples.sample_type IS 'HealthKit sample type: weight, steps, active_energy, etc.';
COMMENT ON COLUMN raw.healthkit_samples.source_name IS 'Device/app that created the sample: Eufy Scale, Apple Watch, etc.';

-- =============================================================================
-- raw.bank_sms - Raw bank SMS messages before parsing
-- =============================================================================
CREATE TABLE raw.bank_sms (
    id BIGSERIAL PRIMARY KEY,
    message_id VARCHAR(100) NOT NULL,      -- chat.db ROWID or hash

    sender VARCHAR(50) NOT NULL,           -- 'ENBD', 'ALRAJHI', etc.
    body TEXT NOT NULL,
    received_at TIMESTAMPTZ NOT NULL,

    -- Parsing result (stored for debugging, but normalized layer is source of truth)
    parsed_ok BOOLEAN DEFAULT FALSE,
    parse_error TEXT,

    -- Ingestion metadata
    source VARCHAR(50) NOT NULL DEFAULT 'imessage',
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    run_id UUID NOT NULL,

    UNIQUE(message_id)
);

CREATE INDEX idx_raw_bank_sms_received ON raw.bank_sms(received_at DESC);
CREATE INDEX idx_raw_bank_sms_sender ON raw.bank_sms(sender);
CREATE INDEX idx_raw_bank_sms_ingested ON raw.bank_sms(ingested_at DESC);

COMMENT ON TABLE raw.bank_sms IS 'Raw bank SMS messages before parsing. Immutable after insert.';
COMMENT ON COLUMN raw.bank_sms.message_id IS 'chat.db ROWID or content hash for deduplication';
COMMENT ON COLUMN raw.bank_sms.parsed_ok IS 'Whether parsing succeeded (normalized.transactions has the parsed result)';

-- =============================================================================
-- raw.manual_entries - Raw manual entries from iOS app
-- =============================================================================
CREATE TABLE raw.manual_entries (
    id BIGSERIAL PRIMARY KEY,
    entry_type VARCHAR(50) NOT NULL,       -- 'food_log', 'mood', 'water', 'workout', 'expense'

    -- Common fields
    timestamp TIMESTAMPTZ NOT NULL,
    date DATE NOT NULL,

    -- Full payload as entered by user
    payload JSONB NOT NULL,

    -- Input context
    input_method VARCHAR(30),              -- 'manual', 'voice', 'photo', 'shortcut'
    device VARCHAR(50),                    -- 'iphone', 'ipad', 'widget'

    -- Ingestion metadata
    source VARCHAR(50) NOT NULL DEFAULT 'ios_app',
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    run_id UUID NOT NULL,

    -- Client-generated ID for idempotency
    client_id VARCHAR(100) UNIQUE
);

CREATE INDEX idx_raw_manual_type_date ON raw.manual_entries(entry_type, date DESC);
CREATE INDEX idx_raw_manual_ingested ON raw.manual_entries(ingested_at DESC);

COMMENT ON TABLE raw.manual_entries IS 'Raw manual entries from iOS app. Immutable after insert.';
COMMENT ON COLUMN raw.manual_entries.entry_type IS 'Type of entry: food_log, mood, water, workout, expense';
COMMENT ON COLUMN raw.manual_entries.client_id IS 'Client-generated UUID for idempotent inserts';

-- =============================================================================
-- Prevent modifications (INSERT only)
-- =============================================================================

-- Create a function to block updates/deletes
CREATE OR REPLACE FUNCTION raw.prevent_modification()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'raw.% is immutable. INSERT only, no UPDATE or DELETE allowed.', TG_TABLE_NAME;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Apply to all raw tables
CREATE TRIGGER prevent_update_whoop_cycles
    BEFORE UPDATE OR DELETE ON raw.whoop_cycles
    FOR EACH ROW EXECUTE FUNCTION raw.prevent_modification();

CREATE TRIGGER prevent_update_whoop_sleep
    BEFORE UPDATE OR DELETE ON raw.whoop_sleep
    FOR EACH ROW EXECUTE FUNCTION raw.prevent_modification();

CREATE TRIGGER prevent_update_whoop_strain
    BEFORE UPDATE OR DELETE ON raw.whoop_strain
    FOR EACH ROW EXECUTE FUNCTION raw.prevent_modification();

CREATE TRIGGER prevent_update_healthkit_samples
    BEFORE UPDATE OR DELETE ON raw.healthkit_samples
    FOR EACH ROW EXECUTE FUNCTION raw.prevent_modification();

CREATE TRIGGER prevent_update_bank_sms
    BEFORE UPDATE OR DELETE ON raw.bank_sms
    FOR EACH ROW EXECUTE FUNCTION raw.prevent_modification();

CREATE TRIGGER prevent_update_manual_entries
    BEFORE UPDATE OR DELETE ON raw.manual_entries
    FOR EACH ROW EXECUTE FUNCTION raw.prevent_modification();

COMMENT ON FUNCTION raw.prevent_modification() IS 'Trigger function to enforce INSERT-only immutability on raw tables';

COMMIT;
