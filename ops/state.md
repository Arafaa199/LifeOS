# LifeOS — Canonical State
Last updated: 2026-01-27T15:00:00+04:00
Owner: Arafa
Control Mode: Autonomous (Human-in-the-loop on alerts only)

---

## OPERATIONAL STATUS

**System Version:** Operational v1
**Operational Start Date:** 2026-01-25
**TRUST-LOCKIN:** PASSED (verified 2026-01-25T16:02+04)
**Coder:** DISABLED (stopped 2026-01-27 — queue empty, no actionable tasks)
**Auditor:** DISABLED (stopped 2026-01-27 — no code changes to review)

### Current State
- Finance ingestion validated and complete
- SMS ingestion FROZEN (no changes to parsing logic since 2026-01-25)
- All launchd services running (exit 0)
- WHOOP → normalized pipeline wired (migration 085)
- DB host: LAN IP (10.0.0.11) for all scripts
- iOS app: SyncCoordinator refactor complete (2026-01-27)

### Verification Results (TRUST-LOCKIN)
- Replay Determinism: PASS
- Coverage Completeness: PASS (0 unexplained gaps)
- Orphan Pending Meals: PASS
- Stable Contracts: PASS (7 schemas documented)

### E2E Reliability (2026-01-26)
- Migration 081: `ops.sync_runs` — advisory locks, freshness view
- Calendar/Finance/Dashboard/Database/n8n: 14/14 smoke tests passed
- iOS: Backend Sync Status section in SettingsView → replaced by Sync Center (2026-01-27)

---

## iOS APP ARCHITECTURE (Updated 2026-01-27)

### SyncCoordinator (NEW — Single Sync Spine)

**Problem solved:** 4 independent refresh paths with no coordination — foreground triggers in NexusApp, ContentView, HealthView, and SettingsView all fetching independently, causing stale data and duplicate requests.

**Architecture:** `SyncCoordinator` singleton owns all sync logic. ViewModels subscribe via Combine.

| Domain | What it does | Old owner | New owner |
|--------|-------------|-----------|-----------|
| dashboard | Fetch `/webhook/nexus-dashboard-today` | DashboardViewModel + HealthViewModel (duplicate!) | SyncCoordinator |
| finance | Fetch `/webhook/nexus-finance-summary` | FinanceViewModel | SyncCoordinator |
| healthKit | HealthKitSyncService.syncAllData() | NexusApp + SettingsView | SyncCoordinator |
| calendar | CalendarSyncService.syncAllData() | NexusApp + SettingsView | SyncCoordinator |

**Data Flow:**
```
NexusApp.onChange(.active) → SyncCoordinator.syncAll()
                                ├── syncDashboard() → $dashboardPayload
                                ├── syncFinance()   → $financeSummaryResult
                                ├── syncHealthKit() → HealthKitSyncService
                                └── syncCalendar()  → CalendarSyncService

DashboardViewModel ─── subscribes to ── $dashboardPayload
HealthViewModel    ─── subscribes to ── $dashboardPayload (no more duplicate fetch)
FinanceViewModel   ─── subscribes to ── $financeSummaryResult
SettingsView       ─── observes ─────── $domainStates (Sync Center UI)
```

**Files changed:**
| File | Change |
|------|--------|
| `Services/SyncCoordinator.swift` | NEW — singleton, 4 domains, Combine publishers, 15s debounce, TaskGroup parallel sync |
| `ViewModels/DashboardViewModel.swift` | Removed network fetch, subscribes to coordinator |
| `Views/Health/HealthView.swift` | Removed duplicate `loadDashboard()`, subscribes to coordinator |
| `ViewModels/FinanceViewModel.swift` | Routes `loadFinanceSummary()` through coordinator |
| `NexusApp.swift` | Replaced HealthKit/Calendar fire-and-forget with `SyncCoordinator.shared.syncAll()` |
| `Views/ContentView.swift` | Removed redundant `.onChange(of: scenePhase)` block |
| `Views/SettingsView.swift` | Replaced scattered sync sections with unified Sync Center UI |

**Commit:** `732ae70 a basic redesign`

---

## STABLE CONTRACTS

**Frozen Date:** 2026-01-26
**Purpose:** Lock database schema contracts to prevent breaking changes without explicit approval.

### finance.transactions — STABLE
- `id` (INTEGER PK), `external_id` (UNIQUE), `client_id` (UNIQUE)
- `transaction_at` (TIMESTAMPTZ, NOT NULL via trigger), `date` (DATE, NOT NULL)
- `amount` (NUMERIC, NOT NULL), `currency` (VARCHAR, DEFAULT 'AED')
- `merchant_name`, `category` (auto-assigned via merchant_rules)
- Invariants: immutable raw events, auto-categorization trigger, Dubai timezone dates

### life.meal_confirmations — STABLE
- `(inferred_meal_date, inferred_meal_time)` UNIQUE
- `user_action`: confirmed | skipped, `confidence` 0.0-1.0

### life.v_inferred_meals — STABLE (VIEW)
- Non-materialized, excludes confirmed/skipped, 30-day window
- Sources: finance.transactions, life.daily_location_summary, life.daily_behavioral_summary

### life.v_coverage_truth — STABLE (VIEW)
- Daily coverage report, zero unexplained gaps required (TRUST-LOCKIN)

### raw.bank_sms — STABLE
- IMMUTABLE (trigger blocks UPDATE/DELETE), `message_id` UNIQUE

### raw.healthkit_samples — STABLE
- IMMUTABLE, `(sample_id, source)` UNIQUE

### raw.calendar_events — STABLE
- IMMUTABLE, `(event_id, source)` UNIQUE

### normalized.* — EXPERIMENTAL
- May be deprecated in favor of direct raw.* → life.daily_facts pipeline

### nutrition.* — EXPERIMENTAL
- Manual-entry only, low usage

---

## SMS INGESTION ARCHITECTURE

**Status:** FROZEN (no changes since 2026-01-25)

```
~/Library/Messages/chat.db
    ├── [fswatch] com.nexus.sms-watcher (instant)
    └── [cron] com.nexus.sms-import (every 15 min)
        └── import-sms-transactions.js
            ├── Reads: chat.db → filters bank senders
            ├── Classifies: sms-classifier.js + sms_regex_patterns.yaml
            └── Writes: finance.transactions (DIRECT — bypasses raw layer)
```

SMS bypasses raw.bank_sms intentionally — idempotency via `external_id` UNIQUE on finance.transactions. Pattern coverage: 99% (343 SMS), capture rate: 92.9%.

---

## COMPLETED TASKS (Summary)

### Recent (Jan 27)
| Task | Status | Summary |
|------|--------|---------|
| SyncCoordinator iOS refactor | DONE | Single sync spine, 4 domains, Combine subscriptions |
| TASK-FEAT.1: GitHub Widget | DONE | `life.get_github_activity_widget(days)` — 8.3ms, streaks, daily breakdown |
| TASK-FIX.11: Feed Status Triggers | DONE | `life.feed_status_live` table + 8 AFTER INSERT triggers, 0.024ms |
| TASK-FIX.10: Receipt Retry | DONE | Exponential backoff (3 retries, 5s/15s/45s) on DB connection |
| TASK-FIX.8: OfflineQueue Atomic | DONE | `OSAllocatedUnfairLock` for thread-safe isProcessing |
| TASK-FIX.7: HealthKit Webhook | DONE | Rewrote n8n workflow, fixed SQL params + field mapping |

### Jan 26-27 (P0/P1 Fixes)
| Task | Status | Summary |
|------|--------|---------|
| TASK-FIX.1: SMS Launchd Path | DONE | Fixed symlink path in plist |
| TASK-FIX.2: Receipt NULL Date | DONE | Added created_at fallback |
| TASK-FIX.3: WHOOP Normalized | DONE | Migration 085 — triggers + backfill |
| TASK-FIX.4: Resolve-Events DB Host | DONE | Tailscale → LAN IP (10.0.0.11) |
| TASK-FIX.5: iOS Timeout | DONE | 5s → 15s foreground timeout |
| TASK-FIX.6: URLRequest Timeout | DONE | 30s timeout on all 8 URLRequest points |
| TASK-FIX.9: Debounce Interval | DONE | 30s → 15s foreground debounce |
| TASK-FIX.12: SMS Architecture Doc | DONE | Documented direct-write rationale |

### Jan 25-26 (Milestones)
- TRUST-LOCKIN: PASSED (replay determinism, coverage, orphan check, contracts)
- M0 (System Trust): COMPLETE — replay script, pipeline health view
- M1 (Daily Financial Truth): COMPLETE — finance views, budgets, dashboard API
- Assisted Capture: COMPLETE — meal inference, HealthKit, calendar
- Reality Verification: COMPLETE — data coverage audit, daily summary view
- E2E Reliability: COMPLETE — sync_runs, smoke tests, iOS observability

### Jan 24 (Phase 0)
- All original tasks (TASK-050 through TASK-090) COMPLETE
- Financial Truth Engine, Behavioral Signals, GitHub Sync, Correlations, Anomaly Detection, Weekly Insights, Budget Alerts, SMS Classifier

---

## SYSTEM CONTEXT

### Key Database Functions
- `finance.to_business_date(ts)` — Dubai timezone date from timestamp
- `dashboard.get_payload()` — Complete dashboard JSON
- `life.refresh_daily_facts(date)` — Refresh daily facts
- `life.get_github_activity_widget(days)` — GitHub activity JSON
- `insights.generate_daily_summary(date)` — Finance summary
- `insights.generate_weekly_report(date)` — Weekly report

### Verification Commands
```bash
# Launchd services
launchctl list | grep -E "nexus|lifeos"

# Feed status
ssh nexus "docker exec nexus-db psql -U nexus -d nexus -c \"SELECT source, status FROM life.feed_status;\""

# Transaction count
ssh nexus "docker exec nexus-db psql -U nexus -d nexus -c \"SELECT COUNT(*) FROM finance.transactions\""

# Daily facts
ssh nexus "docker exec nexus-db psql -U nexus -d nexus -c \"SELECT day, spend_total, recovery_score FROM life.daily_facts ORDER BY day DESC LIMIT 7\""
```

---

## OPERATING CONTRACT (MANDATORY)

### Claude Coder
- Reads tasks **only** from `queue.md`
- Executes one task at a time (topmost READY)
- Must: write migration, apply, prove with SQL, update state.md, mark DONE
- Must NOT ask human unless blocked
- Must NOT start new milestones unless current is DONE

### Auditor Agent
- Verifies correctness, idempotency, invariants
- Writes: Pass/Fail, missing evidence, top 3 risks, smallest unblock step
- P0 risk → write to `alerts.md`

### Human (Arafa)
- Approve/reject via `decisions.md`
- Provide secrets/credentials
- Acknowledge alerts

---

## SYSTEM INVARIANTS

- Every `finance.transaction` has exactly one originating raw_event or receipt
- No duplicate transactions (idempotent via client_id/external_id)
- All times stored as TIMESTAMPTZ, business date via `finance.to_business_date()`
- Financial views are read-only and deterministic
- Views must be replayable from source tables

---

## FROZEN (No Changes)
- SMS parsing patterns (2026-01-25)
- Receipt parsing patterns
- WHOOP sensor mappings
- Core transaction schema
- TodayView.swift (dashboard UI)
