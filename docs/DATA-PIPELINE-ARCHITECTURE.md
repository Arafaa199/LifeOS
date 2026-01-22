# Nexus Data Pipeline Architecture

## Overview

This document describes the three-tier data pipeline architecture for Nexus:

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   raw.*     │ ──► │ normalized.* │ ──► │   facts.*   │
│ (immutable) │     │ (idempotent) │     │ (derived)   │
└─────────────┘     └──────────────┘     └─────────────┘
```

**Goals:**
- Data integrity: Never lose source data
- Reproducibility: Can rebuild derived data from source
- Debuggability: Clear audit trail for every value
- Idempotency: Re-running ingestion produces same result

## Tier 1: Raw Schema (`raw.*`)

### Purpose
Store exact data as received from external sources. **Never modify after insert.**

### Rules
1. **INSERT only** - No UPDATE, no DELETE
2. Store complete payload (JSON when applicable)
3. Track ingestion metadata: `source`, `ingested_at`, `run_id`
4. No data cleaning or transformation
5. Partitioned by date for efficient querying and archival

### Tables

#### `raw.whoop_cycles`
Raw WHOOP cycle data from Home Assistant → n8n.

```sql
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
```

#### `raw.whoop_sleep`
Raw WHOOP sleep data.

```sql
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
```

#### `raw.whoop_strain`
Raw WHOOP strain/workout data.

```sql
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
```

#### `raw.healthkit_samples`
Raw HealthKit data from iOS app webhook.

```sql
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
```

#### `raw.bank_sms`
Raw bank SMS messages before parsing.

```sql
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
```

#### `raw.manual_entries`
Raw manual entries from iOS app (food, mood, notes, etc.).

```sql
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
```

## Tier 2: Normalized Schema (`normalized.*`)

### Purpose
Clean, deduplicated data ready for querying. One row per logical entity.

### Rules
1. **Idempotent** - Re-processing raw data produces identical result
2. Source traceability via `raw_id` foreign key
3. Cleaned values (nulls handled, units standardized)
4. Unique constraints on natural keys
5. UPDATE allowed (for corrections), DELETE discouraged

### Tables

#### `normalized.daily_recovery`
One row per day with WHOOP recovery data.

```sql
CREATE TABLE normalized.daily_recovery (
    date DATE PRIMARY KEY,

    -- Recovery metrics
    recovery_score INT,
    hrv DECIMAL(5,1),
    rhr INT,
    spo2 DECIMAL(4,1),
    skin_temp_c DECIMAL(4,2),

    -- Source tracking
    raw_id BIGINT REFERENCES raw.whoop_cycles(id),
    source VARCHAR(50) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

#### `normalized.daily_sleep`
One row per day with sleep data.

```sql
CREATE TABLE normalized.daily_sleep (
    date DATE PRIMARY KEY,

    -- Timing
    sleep_start TIMESTAMPTZ,
    sleep_end TIMESTAMPTZ,

    -- Duration (in minutes, standardized)
    total_sleep_min INT,
    time_in_bed_min INT,
    light_sleep_min INT,
    deep_sleep_min INT,
    rem_sleep_min INT,
    awake_min INT,

    -- Quality
    sleep_efficiency DECIMAL(5,2),
    sleep_performance INT,
    respiratory_rate DECIMAL(4,1),

    -- Source tracking
    raw_id BIGINT REFERENCES raw.whoop_sleep(id),
    source VARCHAR(50) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

#### `normalized.daily_strain`
One row per day with strain data.

```sql
CREATE TABLE normalized.daily_strain (
    date DATE PRIMARY KEY,

    day_strain DECIMAL(4,1),
    calories_burned INT,
    workout_count INT,
    average_hr INT,
    max_hr INT,

    raw_id BIGINT REFERENCES raw.whoop_strain(id),
    source VARCHAR(50) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

#### `normalized.body_metrics`
Body composition metrics (weight, body fat, etc.).

```sql
CREATE TABLE normalized.body_metrics (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL,

    metric_type VARCHAR(30) NOT NULL,      -- 'weight', 'body_fat', 'muscle_mass'
    value DECIMAL(10,4) NOT NULL,
    unit VARCHAR(10) NOT NULL,             -- Always standardized (kg, %)

    -- Source tracking
    raw_id BIGINT REFERENCES raw.healthkit_samples(id),
    source VARCHAR(50) NOT NULL,
    source_device VARCHAR(100),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- One measurement per type per timestamp
    UNIQUE(date, metric_type, recorded_at)
);

CREATE INDEX idx_normalized_body_date ON normalized.body_metrics(date DESC);
CREATE INDEX idx_normalized_body_type ON normalized.body_metrics(metric_type, date DESC);
```

#### `normalized.transactions`
Parsed and categorized financial transactions.

```sql
CREATE TABLE normalized.transactions (
    id SERIAL PRIMARY KEY,

    -- Core fields
    date DATE NOT NULL,
    merchant_name VARCHAR(200),
    merchant_clean VARCHAR(200),
    amount DECIMAL(12,2) NOT NULL,
    currency VARCHAR(3) NOT NULL,

    -- Categorization
    category VARCHAR(50),
    subcategory VARCHAR(50),
    is_grocery BOOLEAN DEFAULT FALSE,
    is_restaurant BOOLEAN DEFAULT FALSE,
    is_food_related BOOLEAN DEFAULT FALSE,

    -- Bank details
    bank VARCHAR(50),
    card_last_four VARCHAR(4),
    balance_after DECIMAL(12,2),

    -- Flags
    is_recurring BOOLEAN DEFAULT FALSE,
    is_internal_transfer BOOLEAN DEFAULT FALSE,

    -- Source tracking
    raw_id BIGINT REFERENCES raw.bank_sms(id),
    external_id VARCHAR(100) UNIQUE,       -- Dedup key
    source VARCHAR(50) NOT NULL,

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_normalized_txn_date ON normalized.transactions(date DESC);
CREATE INDEX idx_normalized_txn_category ON normalized.transactions(category, date DESC);
```

#### `normalized.food_log`
Normalized food entries with calculated macros.

```sql
CREATE TABLE normalized.food_log (
    id SERIAL PRIMARY KEY,

    logged_at TIMESTAMPTZ NOT NULL,
    date DATE NOT NULL,
    meal_time VARCHAR(20),

    -- Food details
    description TEXT NOT NULL,
    calories INT,
    protein_g DECIMAL(5,1),
    carbs_g DECIMAL(5,1),
    fat_g DECIMAL(5,1),
    fiber_g DECIMAL(5,1),

    -- Context
    confidence VARCHAR(10) DEFAULT 'medium',
    location VARCHAR(30),
    input_method VARCHAR(30),

    -- Source tracking
    raw_id BIGINT REFERENCES raw.manual_entries(id),
    source VARCHAR(50) NOT NULL,

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_normalized_food_date ON normalized.food_log(date DESC);
```

#### `normalized.water_log`
Water intake entries.

```sql
CREATE TABLE normalized.water_log (
    id SERIAL PRIMARY KEY,

    logged_at TIMESTAMPTZ NOT NULL,
    date DATE NOT NULL,
    amount_ml INT NOT NULL,

    raw_id BIGINT REFERENCES raw.manual_entries(id),
    source VARCHAR(50) NOT NULL,

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_normalized_water_date ON normalized.water_log(date DESC);
```

## Tier 3: Facts Schema (`facts.*`)

### Purpose
Pre-computed daily aggregates for fast querying. **Fully derivable from normalized layer.**

### Rules
1. **Derived only** - Computed from normalized tables, never directly inserted
2. **Reproducible** - Can be rebuilt from scratch at any time
3. One row per date
4. Used by dashboards and reporting
5. Refreshed on schedule or triggered by normalized updates

### Tables

#### `facts.daily_health`
Complete daily health summary.

```sql
CREATE TABLE facts.daily_health (
    date DATE PRIMARY KEY,

    -- Recovery (from normalized.daily_recovery)
    recovery_score INT,
    hrv DECIMAL(5,1),
    rhr INT,

    -- Sleep (from normalized.daily_sleep)
    sleep_hours DECIMAL(3,1),
    sleep_quality INT,
    deep_sleep_hours DECIMAL(3,1),
    rem_sleep_hours DECIMAL(3,1),

    -- Strain (from normalized.daily_strain)
    day_strain DECIMAL(4,1),
    calories_burned INT,

    -- Body (from normalized.body_metrics, latest per day)
    weight_kg DECIMAL(5,2),
    body_fat_pct DECIMAL(4,1),

    -- Steps (from normalized.activity_samples)
    steps INT,
    active_calories INT,

    -- Computed
    data_completeness DECIMAL(3,2),        -- 0.00 to 1.00

    -- Refresh tracking
    refreshed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

#### `facts.daily_nutrition`
Daily nutrition summary.

```sql
CREATE TABLE facts.daily_nutrition (
    date DATE PRIMARY KEY,

    -- Totals (from normalized.food_log)
    calories INT,
    protein_g INT,
    carbs_g INT,
    fat_g INT,
    fiber_g INT,

    -- Counts
    meals_logged INT,
    entries_logged INT,

    -- Water (from normalized.water_log)
    water_ml INT,

    -- Confidence assessment
    avg_confidence VARCHAR(10),

    -- Refresh tracking
    refreshed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

#### `facts.daily_finance`
Daily financial summary.

```sql
CREATE TABLE facts.daily_finance (
    date DATE PRIMARY KEY,

    -- Totals (from normalized.transactions)
    total_spent DECIMAL(10,2),
    total_income DECIMAL(10,2),

    -- Category breakdowns
    grocery_spent DECIMAL(10,2),
    food_delivery_spent DECIMAL(10,2),
    restaurant_spent DECIMAL(10,2),
    transport_spent DECIMAL(10,2),
    utilities_spent DECIMAL(10,2),
    shopping_spent DECIMAL(10,2),
    other_spent DECIMAL(10,2),

    -- Counts
    transaction_count INT,

    -- Refresh tracking
    refreshed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

#### `facts.daily_summary`
**Unified daily view** - replaces current `core.daily_summary`.

```sql
CREATE TABLE facts.daily_summary (
    date DATE PRIMARY KEY,

    -- Health (from facts.daily_health)
    weight_kg DECIMAL(5,2),
    recovery_score INT,
    hrv DECIMAL(5,1),
    rhr INT,
    sleep_hours DECIMAL(3,1),
    day_strain DECIMAL(4,1),
    steps INT,

    -- Nutrition (from facts.daily_nutrition)
    calories INT,
    protein_g INT,
    carbs_g INT,
    fat_g INT,
    water_ml INT,

    -- Finance (from facts.daily_finance)
    total_spent DECIMAL(10,2),
    grocery_spent DECIMAL(10,2),

    -- Meta
    data_completeness DECIMAL(3,2),

    -- Refresh tracking
    refreshed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              DATA SOURCES                                    │
├─────────────┬─────────────┬─────────────┬─────────────┬─────────────────────┤
│   WHOOP     │  HealthKit  │  Bank SMS   │  iOS App    │   Home Assistant    │
│  (via HA)   │  (iOS App)  │  (iMessage) │  (manual)   │   (sensors)         │
└──────┬──────┴──────┬──────┴──────┬──────┴──────┬──────┴──────────┬──────────┘
       │             │             │             │                  │
       ▼             ▼             ▼             ▼                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          n8n WEBHOOKS / AUTOMATIONS                          │
│                                                                              │
│  /webhook/nexus-whoop     /webhook/nexus-health    /webhook/nexus-expense   │
│  /webhook/nexus-sleep     /webhook/nexus-weight    /webhook/nexus-food      │
└──────────────────────────────────┬──────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              RAW SCHEMA                                      │
│                                                                              │
│  raw.whoop_cycles    raw.healthkit_samples    raw.bank_sms                  │
│  raw.whoop_sleep     raw.manual_entries                                      │
│  raw.whoop_strain                                                            │
│                                                                              │
│  • INSERT only (immutable)                                                   │
│  • Full payload stored                                                       │
│  • ingested_at, run_id for tracking                                          │
└──────────────────────────────────┬──────────────────────────────────────────┘
                                   │
                                   │ (n8n: normalize workflow)
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           NORMALIZED SCHEMA                                  │
│                                                                              │
│  normalized.daily_recovery    normalized.body_metrics                        │
│  normalized.daily_sleep       normalized.transactions                        │
│  normalized.daily_strain      normalized.food_log                            │
│                               normalized.water_log                           │
│                                                                              │
│  • Unique constraints (idempotent upserts)                                   │
│  • raw_id foreign key for traceability                                       │
│  • Cleaned values, standardized units                                        │
└──────────────────────────────────┬──────────────────────────────────────────┘
                                   │
                                   │ (n8n: nightly aggregation OR trigger)
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                             FACTS SCHEMA                                     │
│                                                                              │
│  facts.daily_health      facts.daily_finance                                 │
│  facts.daily_nutrition   facts.daily_summary                                 │
│                                                                              │
│  • Computed from normalized tables                                           │
│  • Can be rebuilt at any time                                                │
│  • Used by dashboards, MCP server, iOS app                                   │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Refresh Functions

### `facts.refresh_daily_health(target_date DATE)`
Recomputes health facts for a single date.

```sql
CREATE OR REPLACE FUNCTION facts.refresh_daily_health(target_date DATE)
RETURNS VOID AS $$
BEGIN
    INSERT INTO facts.daily_health (
        date,
        recovery_score, hrv, rhr,
        sleep_hours, sleep_quality, deep_sleep_hours, rem_sleep_hours,
        day_strain, calories_burned,
        weight_kg, body_fat_pct,
        steps, active_calories,
        data_completeness,
        refreshed_at
    )
    SELECT
        target_date,
        r.recovery_score, r.hrv, r.rhr,
        (s.total_sleep_min / 60.0)::DECIMAL(3,1),
        s.sleep_performance,
        (s.deep_sleep_min / 60.0)::DECIMAL(3,1),
        (s.rem_sleep_min / 60.0)::DECIMAL(3,1),
        st.day_strain, st.calories_burned,
        w.value, bf.value,
        NULL, NULL,  -- steps/calories from healthkit
        -- Compute completeness
        (
            (CASE WHEN r.recovery_score IS NOT NULL THEN 0.2 ELSE 0 END) +
            (CASE WHEN s.total_sleep_min IS NOT NULL THEN 0.2 ELSE 0 END) +
            (CASE WHEN st.day_strain IS NOT NULL THEN 0.2 ELSE 0 END) +
            (CASE WHEN w.value IS NOT NULL THEN 0.2 ELSE 0 END) +
            0.2  -- placeholder for activity
        )::DECIMAL(3,2),
        NOW()
    FROM
        (SELECT 1) dummy
        LEFT JOIN normalized.daily_recovery r ON r.date = target_date
        LEFT JOIN normalized.daily_sleep s ON s.date = target_date
        LEFT JOIN normalized.daily_strain st ON st.date = target_date
        LEFT JOIN normalized.body_metrics w ON w.date = target_date AND w.metric_type = 'weight'
        LEFT JOIN normalized.body_metrics bf ON bf.date = target_date AND bf.metric_type = 'body_fat'
    ON CONFLICT (date) DO UPDATE SET
        recovery_score = EXCLUDED.recovery_score,
        hrv = EXCLUDED.hrv,
        rhr = EXCLUDED.rhr,
        sleep_hours = EXCLUDED.sleep_hours,
        sleep_quality = EXCLUDED.sleep_quality,
        deep_sleep_hours = EXCLUDED.deep_sleep_hours,
        rem_sleep_hours = EXCLUDED.rem_sleep_hours,
        day_strain = EXCLUDED.day_strain,
        calories_burned = EXCLUDED.calories_burned,
        weight_kg = EXCLUDED.weight_kg,
        body_fat_pct = EXCLUDED.body_fat_pct,
        steps = EXCLUDED.steps,
        active_calories = EXCLUDED.active_calories,
        data_completeness = EXCLUDED.data_completeness,
        refreshed_at = NOW();
END;
$$ LANGUAGE plpgsql;
```

## Migration Strategy

### Phase 1: Create New Schemas (Non-Breaking)
1. Create `raw`, `normalized`, `facts` schemas
2. Create tables with proper constraints
3. Create refresh functions
4. **Existing tables unchanged**

### Phase 2: Dual-Write Period
1. Update n8n workflows to write to both old AND new tables
2. Verify data consistency
3. Run for 1-2 weeks

### Phase 3: Switch Reads
1. Point iOS app / MCP server to `facts.*` tables
2. Keep old tables as backup

### Phase 4: Cleanup
1. After 30 days of stable operation
2. Deprecate old tables
3. Archive or drop

## Rollback Procedure

Each migration will have UP and DOWN scripts.

```bash
# To rollback a migration:
psql -U nexus -d nexus -f migrations/NNNN_description.down.sql
```

If entire architecture needs reverting:
1. n8n workflows already write to old tables (dual-write)
2. Point iOS app back to old tables
3. Drop new schemas if needed

## Success Criteria

- [ ] All raw data preserved indefinitely
- [ ] Re-running normalization produces identical results
- [ ] facts.* tables can be rebuilt from normalized.* in < 5 minutes
- [ ] No data loss during migration
- [ ] iOS app queries return same data as before
- [ ] Ingestion latency < 30 seconds end-to-end
