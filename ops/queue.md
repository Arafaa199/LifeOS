# LifeOS Task Queue

## RULES (MANDATORY)
- Execute topmost task only
- Prove correctness with SQL queries
- No ingestion changes without explicit approval
- Prefer views over tables
- Everything must be replayable from raw data

---

## CURRENT STATUS

Finance ingestion is validated and complete.
SMS ingestion is FROZEN (no changes).
Bank SMS coverage: 100% (143/143)
Overall coverage: 96.1% (6 missing are wallet refunds, not bank TX)

---

## ACTIVE TASK: All Backend Tasks Complete

---

### TASK-DATA.3: Calendar Schema Prep (Backend Only)
Priority: P1
Owner: coder
Status: DONE ✓

**Context:**
- iOS EventKit will eventually POST calendar events
- Need backend ready before iOS work starts

**Objective:** Define schema + webhook contract for calendar ingestion.

**Definition of Done:**
- [x] Migration creating:
  - `raw.calendar_events` (id, event_id, title, start_at, end_at, is_all_day, calendar_name, location, notes, recurrence_rule, client_id, source, created_at)
  - Unique constraint on `(event_id, source)` for idempotency
- [x] `life.v_daily_calendar_summary` view (meeting_count, meeting_hours, first_meeting, last_meeting)
- [x] Example webhook payload JSON documented
- [x] NO n8n workflow yet (iOS not ready)
- [x] Verification: migration applies cleanly, view returns empty result

**Completed:** 2026-01-25T19:00+04
**Evidence:** See state.md
**Result:**
- Migration 068 created and applied successfully
- Table with 13 columns, unique constraint, 2 indexes
- View excludes all-day events from meeting statistics
- Webhook payload example with 4 event types documented
- View returns empty result (no events yet) ✓

---

### TASK-HEALTH.2: HealthKit Schema + Webhook (Backend Only)
Priority: P1
Owner: coder
Status: DONE ✓

**Context:**
- iOS will batch-POST HealthKit samples, workouts, sleep
- Backend must be ready to receive before iOS work begins
- `raw.healthkit_samples` exists with 2 rows (needs schema review)

**Objective:** Create complete HealthKit ingestion backend.

**Definition of Done:**
- [x] Review/update migrations:
  - `raw.healthkit_samples` (sample_id, type, value, unit, start_date, end_date, source_bundle_id, device, client_id, created_at)
  - `raw.healthkit_workouts` (workout_id, type, duration_min, calories, distance_m, start_date, end_date, source, client_id, created_at)
  - `raw.healthkit_sleep` (sleep_id, stage, start_date, end_date, source, client_id, created_at)
  - Unique constraints for idempotency (sample_id, workout_id, sleep_id + source)
- [x] Create `facts.v_health_daily` view aggregating:
  - Steps, active calories, resting calories (sum)
  - Heart rate (avg, min, max)
  - Sleep hours by stage
  - Workout count, total duration
- [x] Create n8n workflow: `POST /webhook/healthkit/batch`
  - Auth: X-API-Key
  - Accepts: `{ client_id, device, source_bundle_id, captured_at, samples:[], workouts:[], sleep:[] }`
  - UPSERT with ON CONFLICT DO NOTHING
  - Returns: `{ success: true, inserted: { samples: N, workouts: N, sleep: N } }`
- [x] Verification queries:
  - `SELECT type, COUNT(*) FROM raw.healthkit_samples GROUP BY type ORDER BY count DESC LIMIT 20`
  - `SELECT * FROM facts.v_health_daily WHERE day >= CURRENT_DATE - 7`
- [x] Example payload JSON for iOS developer reference

**Completed:** 2026-01-25T19:30+04
**Evidence:** See state.md
**Result:**
- Migration 069 created and applied successfully
- Updated raw.healthkit_samples with sample_id, source_bundle_id, client_id columns
- Created raw.healthkit_workouts table (14 columns, unique constraint, 4 indexes, immutability trigger)
- Created raw.healthkit_sleep table (11 columns, unique constraint, 4 indexes, immutability trigger)
- Created facts.v_health_daily view aggregating steps, heart rate, workouts, sleep
- Created n8n workflow: healthkit-batch-webhook.json
- Verified idempotency: ON CONFLICT DO NOTHING working correctly
- Example payload JSON documented with 4 sample types, 2 workouts, 6 sleep stages

---

## COMPLETED TASKS

### TASK-DATA.2: Grocery → Nutrition View
Priority: P0
Owner: coder
Status: DONE ✓

**Objective:** Create joinable view linking grocery purchases to nutrition fields.

**Definition of Done:**
- [x] Create `nutrition.v_grocery_nutrition` view joining:
  - `finance.receipt_items` (item_description, quantity, unit_price)
  - `nutrition.ingredients` (calories, protein, carbs, fat per 100g)
- [x] Fuzzy matching on item name OR exact match on barcode
- [x] Handle unmatched items gracefully (NULL nutrition)
- [x] Do NOT expand ingredient database yet
- [x] Verification query showing matched vs unmatched items

**Completed:** 2026-01-25T18:45+04
**Evidence:** See state.md
**Result:**
- View created using pg_trgm for fuzzy text matching
- 5/90 items (5.6%) matched via fuzzy name matching (0.35-0.45 confidence)
- 85/90 items (94.4%) unmatched (expected - only 21 ingredients in DB)
- Unmatched items return NULL nutrition gracefully
- 3 unique ingredients matched: Greek Yogurt, Sweet Potato, Chicken Breast

### TASK-VIS.1: Read-Only Finance Timeline View
Priority: P0
Owner: coder
Status: DONE ✓

**Objective:** Create a unified timeline view that clearly distinguishes:
- Bank transactions (purchases, ATM, transfers)
- Refunds (money returned)
- Wallet-only events (CAREEM, Amazon notifications - informational only)

**Definition of Done:**
- [x] `finance.v_timeline` view with columns:
  - date, time, event_type (bank_tx | refund | wallet_event | info)
  - amount, currency, merchant, category
  - source (sms, webhook, receipt)
  - is_actionable (true for bank, false for wallet-only)
- [x] Clear visual distinction in output
- [x] SQL proof showing correct classification
- [x] No ingestion changes - read-only view

**Completed:** 2026-01-25
**Evidence:** See state.md

### TASK-DATA.1: Receipt Line Item Extraction
Priority: P0
Status: DONE ✓

**Objective:** Investigate why receipt_items is empty and populate it.

**Definition of Done:**
- [x] Investigate receipt parsing pipeline (n8n workflow, PDF parser)
- [x] Identify why line items aren't being extracted
- [x] Fix extraction or create backfill script
- [x] `finance.receipt_items` populated for existing receipts
- [x] Verification query: `SELECT receipt_id, COUNT(*) FROM finance.receipt_items GROUP BY receipt_id`

**Completed:** 2026-01-25T18:40+04
**Evidence:** See state.md
**Result:** 90 line items extracted from 9 receipts, 100% barcode coverage, all totals verified

### TASK-VIS.2: Unified Daily View
Priority: P1
Status: DONE ✓

**Objective:** Enhance `life.get_daily_summary()` to include finance timeline.

**Definition of Done:**
- [x] Add `timeline` array to `finance` section in daily summary
- [x] Timeline includes: time, type, amount, currency, merchant, category, source, actionable
- [x] Timeline sorted by event_time DESC (most recent first)
- [x] Backward compatible (all original finance keys preserved)
- [x] Empty array `[]` for days with no transactions
- [x] Performance < 50ms (achieved 8.95ms)

**Completed:** 2026-01-25
**Evidence:** See state.md

### TASK-ENV.1: Smart Home Metrics
Priority: P2
Status: DONE ✓

**Objective:** Ingest temperature, humidity, power consumption from HA.

**Definition of Done:**
- [x] Create `home.power_log` table for power consumption tracking
- [x] Create views: `v_daily_temperature`, `v_daily_humidity`, `v_daily_power`, `v_environment_summary`
- [x] Create `life.get_environment_summary(date)` function
- [x] Create n8n workflows for HA sensor sync (environment-metrics-sync, power-metrics-sync)
- [x] Verify views work correctly with test data

**Completed:** 2026-01-25
**Evidence:** See state.md

---

## ROADMAP: Life Data Ingestion

### Phase 1: Finance (COMPLETE)
- [x] Bank SMS (EmiratesNBD, AlRajhi, JKB)
- [x] Receipt parsing (Carrefour, etc.)
- [x] Manual expense entry (webhook)
- [x] Finance timeline view (v_timeline)

### Phase 1b: Finance Data Quality (IN PROGRESS)
- [ ] Receipt line item extraction (DATA.1)
- [ ] Grocery → nutrition linking (DATA.2)

### Phase 2: Health (BACKEND PREP)
- [x] WHOOP (recovery, HRV, sleep, strain) via HA
- [x] Weight (Eufy scale -> HealthKit -> iOS app)
- [ ] HealthKit schema + webhook (HEALTH.2 - backend only)
- [ ] Apple Watch (steps, calories, workouts) - iOS DEFERRED
- [ ] Sleep tracking (Apple Watch native) - iOS DEFERRED

### Phase 3: Behavioral (COMPLETE)
- [x] Location (HA person tracking)
- [x] Sleep/wake detection (HA motion sensors)
- [x] TV sessions (Samsung TV state)

### Phase 4: Productivity (BACKEND PREP)
- [x] GitHub activity (commits, PRs, issues)
- [ ] Calendar schema + webhook (DATA.3 - backend only)
- [ ] Calendar (iOS EventKit) - iOS DEFERRED
- [ ] Screen time - iOS DEFERRED

### Phase 5: Environment (COMPLETE)
- [x] Smart home sensors (temperature, humidity)
- [x] Power consumption (Tuya plugs)
- [x] Environment metrics views + n8n workflows

### Phase 6: Communication (NOT STARTED)
- [ ] Email patterns (send/receive counts, not content)
- [ ] Message patterns (volume, not content)

---

## FROZEN (No Changes)
- SMS ingestion pipeline
- Receipt parsing pipeline
- WHOOP sync

## DEFERRED (iOS Implementation Required)
- **TASK-HEALTH.1**: Apple Watch iOS Integration (sync steps, calories, workouts)
  - Backend prep (HEALTH.2) must complete first
  - Will be queued when iOS work is approved
- **Calendar iOS**: EventKit integration for calendar sync
  - Backend prep (DATA.3) must complete first
- **Screen Time**: iOS screen time API integration
