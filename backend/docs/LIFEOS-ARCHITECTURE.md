# LifeOS Architecture

## Overview

LifeOS is the unified data model for all Nexus life tracking data. It provides a canonical event envelope that all data sources feed into, enabling consistent querying, correlation, and derivation across health, finance, and behavioral signals.

## Canonical Day Boundary

**Timezone: Asia/Dubai (UTC+4)**

All daily aggregations use Asia/Dubai timezone for day boundaries. This ensures:
- Sleep that ends at 2 AM belongs to that day's summary (not previous day)
- Financial transactions use local time, not UTC
- All sources align on the same day boundary

```sql
-- Canonical day for a timestamp
SELECT (timestamp AT TIME ZONE 'Asia/Dubai')::date AS canonical_date;

-- Day boundary in UTC for queries
SELECT date_trunc('day', timestamp AT TIME ZONE 'Asia/Dubai') AT TIME ZONE 'Asia/Dubai' AS day_start_utc;
```

## Canonical Event Model

### `life.event_raw` - Unified Event Envelope

Every piece of data entering Nexus flows through a unified envelope that captures:
- **What** happened (event type and payload)
- **When** it happened (multiple timestamps)
- **Where** it came from (source chain)
- **How confident** we are (quality indicators)

```sql
CREATE TABLE life.event_raw (
    -- Identity
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type VARCHAR(100) NOT NULL,       -- 'health.weight', 'finance.transaction', 'behavior.home_arrival'

    -- Canonical timestamps
    occurred_at TIMESTAMPTZ NOT NULL,       -- When the event actually happened
    canonical_date DATE NOT NULL,           -- Day bucket (Asia/Dubai timezone)

    -- Source chain (who reported this and when)
    source_system VARCHAR(50) NOT NULL,     -- 'healthkit', 'whoop', 'bank_sms', 'home_assistant', 'manual'
    source_device VARCHAR(100),             -- 'eufy_scale', 'apple_watch', 'iphone', null
    source_subsystem VARCHAR(100),          -- 'hacs_whoop', 'n8n_webhook', 'fswatch'
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Deduplication
    external_id VARCHAR(255),               -- Source-specific ID for dedup
    content_hash VARCHAR(64),               -- SHA256 of payload for content-based dedup

    -- Payload
    payload JSONB NOT NULL,                 -- Event-specific data

    -- Quality indicators
    confidence VARCHAR(20) DEFAULT 'high',  -- 'high', 'medium', 'low', 'estimated'
    is_backfill BOOLEAN DEFAULT FALSE,      -- Was this retroactively added?
    is_correction BOOLEAN DEFAULT FALSE,    -- Does this override a previous value?
    supersedes_id UUID REFERENCES life.event_raw(id),  -- If correction, what did it replace?

    -- Processing state
    processed_at TIMESTAMPTZ,               -- When normalized
    process_error TEXT,                     -- If normalization failed

    -- Constraints
    UNIQUE(event_type, external_id),
    UNIQUE(event_type, content_hash) WHERE content_hash IS NOT NULL
);

-- Indexes for common access patterns
CREATE INDEX idx_event_raw_type_date ON life.event_raw(event_type, canonical_date DESC);
CREATE INDEX idx_event_raw_source ON life.event_raw(source_system, ingested_at DESC);
CREATE INDEX idx_event_raw_unprocessed ON life.event_raw(event_type) WHERE processed_at IS NULL;
```

### Event Types Hierarchy

```
health.*
  health.weight           -- Body weight measurement
  health.body_fat         -- Body composition
  health.sleep            -- Sleep session
  health.recovery         -- WHOOP recovery score
  health.strain           -- WHOOP day strain
  health.hrv              -- Heart rate variability
  health.rhr              -- Resting heart rate
  health.steps            -- Step count
  health.active_calories  -- Active energy burned

nutrition.*
  nutrition.food_log      -- Food entry
  nutrition.water         -- Water intake

finance.*
  finance.transaction     -- Bank transaction (SMS or receipt)
  finance.income          -- Income received
  finance.budget_alert    -- Budget threshold crossed

behavior.*
  behavior.home_arrival   -- Arrived home
  behavior.home_departure -- Left home
  behavior.sleep_detected -- Motion sensors suggest sleep
  behavior.wake_detected  -- Morning activity detected
```

## Finance Ingestion Pipeline

### SMS-First Architecture

Bank SMS is the **primary source of truth** for transactions. All other sources (receipts, manual entries) are supplementary.

```
Bank SMS → chat.db fswatch → n8n parse → life.event_raw → normalized.transactions
                                              ↑
Gmail PDF Receipts ──────────────────────────┘ (linked, not primary)
```

### SMS Deduplication Contract

Each bank SMS has a unique fingerprint:

```sql
-- Dedup key for bank SMS
content_hash = SHA256(
    sender || '|' ||
    TRIM(amount) || '|' ||
    TRIM(merchant) || '|' ||
    DATE(received_at AT TIME ZONE 'Asia/Dubai')
)
```

Rules:
1. Same hash within 24 hours = duplicate, skip
2. Same hash after 24 hours = new transaction (recurring payment)
3. Multiple cards → different sender prefixes (ENBD vs FAB) → not duplicates

### SMS Parsing Contract

```typescript
interface ParsedSMS {
    bank: 'ENBD' | 'FAB' | 'ADCB' | 'CBD';
    card_last_four: string;
    amount: number;
    currency: 'AED' | 'USD' | 'EUR';
    merchant_raw: string;
    merchant_clean: string;  // Normalized name
    category_hint: string;   // From merchant mapping
    balance_after?: number;
    timestamp: Date;         // SMS received time (close to transaction time)
}
```

### Gmail PDF Receipt Pipeline

Receipts are **secondary data** that enrich transactions, not replace them.

```
Gmail → PDF attachment → Google Document AI → Extract line items
                                                    ↓
                                            Link to existing transaction
                                            (match by merchant + amount + date)
```

Receipt data stored in event payload:
```json
{
  "event_type": "finance.transaction",
  "source_system": "gmail_receipt",
  "payload": {
    "receipt_vendor": "Carrefour",
    "receipt_date": "2026-01-15",
    "total_amount": 156.50,
    "currency": "AED",
    "line_items": [
      {"name": "Milk 1L", "qty": 2, "price": 7.50},
      {"name": "Bread", "qty": 1, "price": 4.00}
    ],
    "linked_transaction_id": "uuid-of-sms-transaction"
  }
}
```

Matching logic:
1. Same merchant (fuzzy match)
2. Same amount (exact)
3. Same date (±1 day)
4. If match found → link receipt to transaction, mark `has_receipt = true`
5. If no match → store as standalone receipt event (manual reconciliation later)

## Health Ingestion Unification

### Current Sources

| Source | Data Types | Path |
|--------|-----------|------|
| WHOOP | Recovery, HRV, RHR, Sleep, Strain | HA → n8n (15 min poll) |
| Eufy Scale | Weight, Body Fat | HealthKit → iOS App → webhook |
| Apple Watch | Steps, Calories, Workout | HealthKit → iOS App → webhook |
| Manual | Mood, Energy, Notes | iOS App → webhook |

### Unified Health Event

All health data flows through `life.event_raw` with event_type `health.*`:

```json
{
  "event_type": "health.weight",
  "occurred_at": "2026-01-15T07:30:00+04:00",
  "canonical_date": "2026-01-15",
  "source_system": "healthkit",
  "source_device": "eufy_scale",
  "payload": {
    "value": 78.5,
    "unit": "kg"
  },
  "confidence": "high"
}
```

### WHOOP Data Contract

WHOOP data arrives via Home Assistant HACS integration → n8n polling.

```json
{
  "event_type": "health.recovery",
  "occurred_at": "2026-01-15T06:00:00+04:00",
  "canonical_date": "2026-01-15",
  "source_system": "whoop",
  "source_subsystem": "hacs_whoop",
  "payload": {
    "recovery_score": 78,
    "hrv_ms": 45.2,
    "rhr_bpm": 52,
    "spo2_pct": 97.5,
    "skin_temp_c": 33.2,
    "cycle_id": 123456789
  }
}
```

### Daily Health Derivation

`facts.daily_health` is derived from normalized health events:

```sql
-- Priority order for metrics with multiple sources
-- 1. WHOOP (most accurate for HRV, RHR, Sleep)
-- 2. Apple Watch (steps, active calories)
-- 3. Eufy Scale (weight, body fat)
-- 4. Manual entries (mood, energy)

SELECT
    canonical_date,
    -- Recovery: WHOOP only
    (SELECT (payload->>'recovery_score')::int FROM life.event_raw
     WHERE event_type = 'health.recovery' AND canonical_date = d.date
     ORDER BY occurred_at DESC LIMIT 1) AS recovery_score,

    -- Weight: Eufy > Manual
    (SELECT (payload->>'value')::decimal FROM life.event_raw
     WHERE event_type = 'health.weight' AND canonical_date = d.date
     ORDER BY
       CASE source_system WHEN 'healthkit' THEN 1 WHEN 'manual' THEN 2 END,
       occurred_at DESC
     LIMIT 1) AS weight_kg
FROM generate_series(...) d(date);
```

## Home Assistant Behavioral Signals

### Philosophy

Capture **behavioral signals**, not full telemetry. We don't need every motion sensor state change - we need meaningful life events.

### Relevant Signals

| Signal | HA Trigger | Event Type |
|--------|-----------|------------|
| Home arrival | Device tracker home + door open | `behavior.home_arrival` |
| Home departure | Device tracker away | `behavior.home_departure` |
| Sleep detected | Living room motion off + bedroom motion + lights off for 30 min | `behavior.sleep_detected` |
| Wake detected | Kitchen motion + lights on (morning hours) | `behavior.wake_detected` |
| Work session | Office motion sustained for 1+ hour | `behavior.work_session` |

### Implementation

n8n workflow triggered by HA webhooks:

```yaml
# HA automation → n8n webhook
automation:
  - alias: "Nexus: Home Arrival"
    trigger:
      - platform: state
        entity_id: device_tracker.iphone
        to: 'home'
    condition:
      - condition: state
        entity_id: binary_sensor.front_door_contact
        state: 'on'
        for: "00:00:30"
    action:
      - service: rest_command.nexus_behavior
        data:
          event_type: "behavior.home_arrival"
          occurred_at: "{{ now().isoformat() }}"
```

### What We DON'T Capture

- Individual motion sensor states (too noisy)
- Light on/off events (not meaningful alone)
- Temperature sensor readings (not behavioral)
- Device states without behavioral meaning

## Agent Prompts

### Background Coder (Claude Coder)

```
You are the Nexus implementation agent.

Your goal is to make the system **boring, reliable, and extensible**.

**Do not add UI features, AI features, or new integrations.**

## Priority Rules
1. Data integrity > convenience
2. Idempotency > speed
3. Explicit > clever
4. Boring > exciting

## Architecture Constraints
- All data flows through life.event_raw
- All timestamps use Asia/Dubai for day boundaries
- All ingestion must be idempotent (re-running = same result)
- All derived data must be reproducible (can rebuild from events)

## What You Can Do
- Create database migrations (with rollback)
- Update n8n workflows for data pipelines
- Add constraints and indexes
- Implement normalization functions

## What You Cannot Do
- Add UI features to iOS app
- Add AI/ML features
- Create new integrations
- Change data semantics without migration
```

### Background Auditor (Claude Code Auditor)

```
You are the Nexus audit agent.

Your job is to **assume failure, misuse, and partial compromise**.

## Audit Focus Areas

### Data Integrity
- Duplicate ingestion across sources (SMS + receipt for same transaction)
- Timezone bugs (event at 11 PM appears in wrong day)
- Source conflicts (WHOOP and Apple Watch disagree on sleep)
- Silent normalization failures (event_raw grows but facts.* doesn't)

### Pipeline Health
- Check life.event_raw for unprocessed events (processed_at IS NULL)
- Check for gaps in daily data (missing days in facts.daily_*)
- Check for anomalies (weight jump > 2kg in a day)
- Check ingestion latency (ingested_at - occurred_at > 1 hour)

### Security Boundaries
- n8n webhook authentication (are sensitive endpoints protected?)
- Database role separation (ingest vs read-only)
- HA token exposure (is it in logs?)

## Output Format
Ranked list of risks with:
1. Severity (critical/high/medium/low)
2. Concrete scenario showing failure
3. Minimal fix (not a redesign)
```

### Active Session Architect

```
You are assisting with Nexus development in an interactive session.

## Context Awareness
- LifeOS canonical event model: life.event_raw → normalized.* → facts.*
- Timezone: Asia/Dubai for all day boundaries
- Primary sources: WHOOP (health), Bank SMS (finance), HealthKit (body metrics)

## When Asked About Data
1. Check life.event_raw first (source of truth)
2. Check normalized.* for cleaned data
3. Check facts.* for aggregated views

## When Asked to Implement
1. Always write migrations (up + down)
2. Always maintain idempotency
3. Never break existing queries without migration path
4. Prefer explicit over clever

## When Debugging
1. Check ingestion: Is data in life.event_raw?
2. Check normalization: Is processed_at set?
3. Check aggregation: Is facts.* up to date?
4. Check timezone: Is canonical_date correct?
```

## Migration Path

### From Current Schema to LifeOS

1. **Create life schema and event_raw table** (non-breaking)
2. **Dual-write period**: All ingestion writes to both old tables AND life.event_raw
3. **Verify data parity**: Compare old tables with derived views from life.event_raw
4. **Switch reads**: Update iOS app and MCP to read from facts.*
5. **Deprecate old tables**: After 30 days of stable operation

### Rollback

If issues arise:
1. n8n still writes to old tables (dual-write)
2. iOS app can be pointed back to old tables
3. life.event_raw can be dropped without data loss (old tables still have data)
