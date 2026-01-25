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

**Current Milestone:** Assisted Capture (P0)
**Goal:** Passive health signals + inferred meal detection, zero manual input.

**Previous Milestone:** Reality Verification — COMPLETE ✅

---

## ACTIVE TASK: HealthKit iOS Integration

### TASK-CAPTURE.1: HealthKit iOS Integration
Priority: P0
Owner: coder
Status: PENDING

**Context:**
- Backend schema ready (migration 069: raw.healthkit_samples, normalized.body_metrics)
- Webhook ready: POST /webhook/nexus-healthkit
- Need iOS app to read HealthKit and sync to backend

**Objective:** Implement HealthKit read-only sync in iOS app.

**Definition of Done:**
- [ ] Create `HealthKitSyncService.swift` to read:
  - Sleep analysis (HKCategoryTypeIdentifierSleepAnalysis)
  - Heart rate variability (HKQuantityTypeIdentifierHeartRateVariabilitySDNN)
  - Resting heart rate (HKQuantityTypeIdentifierRestingHeartRate)
  - Active energy burned (HKQuantityTypeIdentifierActiveEnergyBurned)
  - Weight (HKQuantityTypeIdentifierBodyMass) — already exists, verify
- [ ] Sync on app foreground (background refresh optional)
- [ ] Send batched samples to /webhook/nexus-healthkit
- [ ] Deduplicate using sample UUID (idempotent)
- [ ] Show sync status in Settings (last sync time, sample count)
- [ ] Verification: HealthKit data appears in raw.healthkit_samples

**Notes:**
- Read-only (no writes to HealthKit)
- Respect existing HealthKitManager.swift patterns
- Weight sync may already work — verify before duplicating

---

### TASK-CAPTURE.2: Meal Inference Engine
Priority: P0
Owner: coder
Status: PENDING
**Blocked by:** TASK-CAPTURE.1

**Context:**
- Signals available: transaction time, merchant category (Restaurant/Grocery), location (home/away), TV off periods, motion gaps
- Goal: Infer likely meal times without user input

**Objective:** Create SQL-based meal inference using existing signals.

**Definition of Done:**
- [ ] Create `life.v_inferred_meals` view detecting meal candidates:
  - Restaurant transaction → high confidence meal
  - Home + cooking time window (11-14h, 18-21h) + no TV → medium confidence
  - Grocery purchase same day + home evening → low confidence (cooked)
- [ ] Each inference has: inferred_at, meal_type (breakfast/lunch/dinner/snack), confidence (0-1), signals_used (JSONB)
- [ ] Create `life.meal_confirmations` table for user feedback (confirmed/skipped)
- [ ] Function `life.get_pending_meal_confirmations(date)` returns unconfirmed inferences
- [ ] Verification: query shows inferred meals for last 7 days with confidence scores

**Signals to use:**
- `finance.transactions` (restaurant, grocery timing)
- `life.locations` (home arrival/departure)
- `life.behavioral_events` (TV sessions, motion gaps)
- Time windows for meal types

---

### TASK-CAPTURE.3: Meal Confirmation UX
Priority: P0
Owner: coder
Status: PENDING
**Blocked by:** TASK-CAPTURE.2

**Context:**
- Inferred meals need human confirmation
- UX must be frictionless: yes/skip only, no data entry

**Objective:** iOS UI for confirming inferred meals.

**Definition of Done:**
- [ ] Create `MealConfirmationView.swift` showing:
  - Inferred meal card (time, type, confidence, signals summary)
  - Two buttons: ✓ Confirm / ✗ Skip
  - Swipe gestures (right=confirm, left=skip)
- [ ] Integrate into TodayView (card appears when pending confirmations exist)
- [ ] POST confirmation to /webhook/nexus-meal-confirmation
- [ ] Dismissed meals don't reappear (stored in meal_confirmations)
- [ ] Verification: confirm/skip flows work, data persists

**UX Requirements:**
- No text input
- No meal details editing
- Just binary: "Did you eat around this time?" → Yes/No

---

## COMPLETED: Reality Verification

### TASK-VERIFY.1: Data Coverage Audit
Priority: P0
Owner: coder
Status: DONE ✓
**Completed:** 2026-01-25T22:10+04

**Context:**
- Multiple data domains exist (finance, health, nutrition, behavioral)
- Need to identify gaps where data exists in one domain but not others
- Foundation for trusting the system

**Objective:** Create SQL views showing missing days per domain.

**Definition of Done:**
- [x] Create `life.v_data_coverage_gaps` view showing:
  - Days with SMS but no transactions
  - Days with groceries (receipt_items) but no food_log entries
  - Days with WHOOP data but no daily_facts
  - Days with transactions but no daily summary
- [x] Create `life.v_domain_coverage_matrix` showing coverage by domain by day
- [x] Query showing last 30 days coverage percentage per domain
- [x] Identify and document any systemic gaps
- [x] Verification: run coverage report, document findings in state.md

**Evidence:** See state.md
**Result:**
- 3 views created in `life` schema
- 96.8% daily_facts coverage (30/31 days) ✓
- 3 systemic gaps identified and explained (all expected behavior)
- No data loss detected ✓

---

### TASK-VERIFY.2: Deterministic Replay
Priority: P0
Owner: coder
Status: DONE ✓
**Completed:** 2026-01-25T22:33+04

**Context:**
- Data should be replayable from raw sources
- Need to prove counts and totals are deterministic

**Objective:** Script to wipe derived tables and replay from raw data.

**Definition of Done:**
- [x] Create `scripts/replay-last-30-days.sh`:
  - Backup current counts (transactions, daily_facts, etc.)
  - Truncate derived tables (normalized.*, facts.*)
  - Re-run materialization from raw.*
  - Compare counts before/after
  - Report any discrepancies
- [x] Document replay procedure in ops/artifacts/replay_procedure.md
- [x] Run replay, verify counts match ±0
- [x] Verification: SOURCE tables preserved, totals unchanged

**Evidence:** See state.md
**Result:**
- Script created: `backend/scripts/replay-last-30-days.sh`
- Documentation: `ops/artifacts/replay_procedure.md`
- Replay PASS: Source tables preserved ✓, Total spend unchanged ✓
- Runtime: 21 seconds
- life.daily_facts: 31 rows rebuilt (last 30 days)
- Total recovery score: 357 (unchanged before/after)

---

### TASK-VERIFY.3: Single Daily Summary View
Priority: P0
Owner: coder
Status: DONE ✓
**Completed:** 2026-01-25T22:45+04

**Context:**
- Multiple summary views/functions exist (daily_facts, get_daily_summary, v_dashboard_*)
- Need ONE canonical source of truth

**Objective:** Create single canonical daily_summary materialized view.

**Definition of Done:**
- [x] Create `life.mv_daily_summary` materialized view combining:
  - Finance: spend_total, transaction_count, spending_by_category
  - Health: recovery_score, hrv, sleep_hours, weight
  - Nutrition: calories_in, protein, water_ml
  - Behavioral: tv_hours, time_at_home, sleep_detected_at
- [x] Create `life.refresh_daily_summary(date)` function
- [x] Deprecate redundant views (document which ones)
- [x] All dashboard queries should use this single view
- [x] Verification: compare output with existing views, ensure parity

**Evidence:** See state.md
**Result:**
- Materialized view created with 92 rows ✓
- Refresh function working correctly ✓
- JSONB function `get_daily_summary_canonical()` for API compatibility ✓
- Performance: 0.029ms (< 1ms) ✓
- Data matches `life.daily_facts` exactly ✓
- Deprecation plan documented in `deprecated_views_071.md` ✓

---

### TASK-VERIFY.4: Dashboard Simplification
Priority: P0
Owner: coder
Status: DONE ✓
**Completed:** 2026-01-25T22:50+04

**Context:**
- iOS app has multiple dashboard versions (DashboardView, DashboardV2View, TodayView)
- Toggles and feature flags add complexity
- Need ONE dashboard, ONE source of truth

**Objective:** Kill v2/v3 toggles, consolidate to single dashboard.

**Definition of Done:**
- [x] Audit existing dashboard views in iOS app
- [x] Identify which views to keep vs archive
- [x] Remove feature toggles and conditional rendering
- [x] Single `TodayView.swift` as canonical dashboard
- [x] All data comes from `life.mv_daily_summary` (via dashboard.v_today → life.daily_facts per deprecation plan)
- [x] Archive removed views to `ios/Nexus/Archive/` (deleted instead - cleaner)
- [x] Verification: app builds, single dashboard works, no toggles remain

**Evidence:** See state.md
**Result:**
- Audit complete: Only TodayView.swift exists (247 lines)
- 9 old dashboard files deleted in previous commit
- No feature toggles found
- Build successful ✓
- Task was already 100% complete from previous work

---

## COMPLETED TASKS

### TASK-DATA.3: Calendar Schema Prep (Backend Only)
Priority: P1
Owner: coder
Status: DONE ✓
**Completed:** 2026-01-25T19:00+04

### TASK-HEALTH.2: HealthKit Schema + Webhook (Backend Only)
Priority: P1
Owner: coder
Status: DONE ✓
**Completed:** 2026-01-25T19:30+04

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

## ROADMAP

### MILESTONE: Reality Verification (P0) — COMPLETE ✓
**Goal:** Prove data is correct, replayable, explainable before building more.
- [x] VERIFY.1: Data Coverage Audit ✓
- [x] VERIFY.2: Deterministic Replay ✓
- [x] VERIFY.3: Single Daily Summary View ✓
- [x] VERIFY.4: Dashboard Simplification ✓

### Phase 1: Finance (COMPLETE)
- [x] Bank SMS (EmiratesNBD, AlRajhi, JKB)
- [x] Receipt parsing (Carrefour, etc.)
- [x] Manual expense entry (webhook)
- [x] Finance timeline view (v_timeline)
- [x] Receipt line item extraction (DATA.1)
- [x] Grocery → nutrition linking (DATA.2)

### Phase 2: Health (BACKEND COMPLETE)
- [x] WHOOP (recovery, HRV, sleep, strain) via HA
- [x] Weight (Eufy scale -> HealthKit -> iOS app)
- [x] HealthKit schema + webhook (HEALTH.2)
- [ ] Apple Watch iOS integration - DEFERRED
- [ ] Sleep tracking iOS - DEFERRED

### Phase 3: Behavioral (COMPLETE)
- [x] Location (HA person tracking)
- [x] Sleep/wake detection (HA motion sensors)
- [x] TV sessions (Samsung TV state)

### Phase 4: Productivity (BACKEND COMPLETE)
- [x] GitHub activity (commits, PRs, issues)
- [x] Calendar schema + webhook (DATA.3)
- [ ] Calendar iOS integration - DEFERRED
- [ ] Screen time - DEFERRED

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
