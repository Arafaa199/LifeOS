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

## ACTIVE TASK: Unified Daily View

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

---

## ROADMAP: Life Data Ingestion

### Phase 1: Finance (COMPLETE)
- [x] Bank SMS (EmiratesNBD, AlRajhi, JKB)
- [x] Receipt parsing (Carrefour, etc.)
- [x] Manual expense entry (webhook)

### Phase 2: Health (PARTIAL)
- [x] WHOOP (recovery, HRV, sleep, strain) via HA
- [x] Weight (Eufy scale -> HealthKit -> iOS app)
- [ ] Apple Watch (steps, calories, workouts) - needs iOS work
- [ ] Sleep tracking (Apple Watch native) - needs iOS work

### Phase 3: Behavioral (COMPLETE)
- [x] Location (HA person tracking)
- [x] Sleep/wake detection (HA motion sensors)
- [x] TV sessions (Samsung TV state)

### Phase 4: Productivity (PARTIAL)
- [x] GitHub activity (commits, PRs, issues)
- [ ] Calendar (iOS EventKit) - needs iOS work
- [ ] Screen time - needs iOS work

### Phase 5: Environment (NOT STARTED)
- [ ] Smart home sensors (temperature, humidity)
- [ ] Power consumption (Tuya plugs)
- [ ] 3D printer activity (Moonraker)

### Phase 6: Communication (NOT STARTED)
- [ ] Email patterns (send/receive counts, not content)
- [ ] Message patterns (volume, not content)

---

## NEXT TASKS (After VIS.1)

### TASK-VIS.2: Unified Daily View
Priority: P1
Status: READY

Enhance `life.get_daily_summary()` to include finance timeline.

### TASK-HEALTH.1: Apple Watch Integration
Priority: P1
Status: BLOCKED (iOS work)

Sync steps, active calories, workouts from HealthKit.

### TASK-ENV.1: Smart Home Metrics
Priority: P2
Status: READY

Ingest temperature, humidity, power consumption from HA.

---

## FROZEN (No Changes)
- SMS ingestion pipeline
- Receipt parsing pipeline
- WHOOP sync

## DEFERRED (iOS Required)
- Apple Watch health data
- Calendar integration
- Screen time
