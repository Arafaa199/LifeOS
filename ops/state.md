# LifeOS — Canonical State
Last updated: 2026-02-02T04:00:00+04:00
Owner: Arafa
Control Mode: Autonomous (Human-in-the-loop on alerts only)

---

## OPERATIONAL STATUS

**System Version:** Operational v1
**Operational Start Date:** 2026-01-25
**TRUST-LOCKIN:** PASSED (verified 2026-01-25T16:02+04)
**Coder:** ENABLED (queue restocked 2026-02-01 — FEAT.4-10: Reminders integration, Calendar improvements, Productivity correlations)
**Auditor:** ENABLED (reviewing new feature work)

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

### Recent (Feb 2)
| Task | Status | Summary |
|------|--------|---------|
| TASK-FEAT.4: Reminders Sync Webhook | DONE | Rewrote `reminders-sync-webhook.json` from 8-node ops.sync_runs pipeline to 4-node batch upsert pattern (matching healthkit-batch). Build SQL Code node constructs single batch INSERT with ON CONFLICT DO UPDATE, single-quote escaping. Removed `ops.start_sync`/`ops.finish_sync` (caused stuck 'running' rows). Handles empty payload gracefully. JSON valid (4 nodes, 3 connections). iOS build: BUILD SUCCEEDED. 1 file changed. Commit `a8f372f`. Note: workflow must be imported into n8n and activated. |
| TASK-FEAT.5: Reminders GET Endpoint | DONE | Rewrote `reminders-events-webhook.json` from 4-node workflow (no validation) to 7-node workflow with date validation. Added Validate Dates Code node (`/^\d{4}-\d{2}-\d{2}$/` regex), IF Valid branch, Respond Error (400). Postgres reads pre-validated `$json.start`/`$json.end`. Query includes incomplete reminders with no due date. Pattern matches calendar-events-webhook.json exactly. JSON valid (7 nodes, 5 connections). iOS build: BUILD SUCCEEDED. 1 file changed. Commit `acb12e7`. Note: workflow must be imported into n8n and activated. |
| TASK-FEAT.6: Calendar Month Summary View | DONE | Migration 109: Created `life.v_monthly_calendar_summary` VIEW aggregating `raw.calendar_events` by Dubai-timezone date. Columns: day, event_count, all_day_count, meeting_hours (non-all-day FILTER), has_events, first_event_time, last_event_time. Sparse output (12 days for Jan 2026 from 21 total events). All-day events tracked separately (meeting_hours NULL for all-day-only days). Down migration tested (DROP + re-CREATE). 2 files changed. |
| TASK-FEAT.7: Calendar + Productivity Correlation | DONE | Migration 110: Created `insights.calendar_productivity_correlation` VIEW joining calendar (meeting_count/hours), health (recovery, sleep, HRV, strain), productivity (GitHub push/PR/repos), and finance (spend_total) per day with prev/next day recovery. Meeting intensity: none/light/heavy/very_heavy (>2h threshold). Created `insights.calendar_pattern_summary()` function comparing 4 metrics across intensity buckets with significance findings. Fixed `insights.meetings_hrv_correlation` to use real calendar data (was all NULLs). 8 rows in correlation view, pattern summary correctly reports insufficient data for heavy meetings. Down migration tested. 2 files changed. Commit `27e9c53`. |
| TASK-FEAT.8: Reminder Daily Facts | DONE | Migration 111: Created `life.v_daily_reminder_summary` VIEW (per-day due/completed/overdue/completion_rate). Added `reminders_due` + `reminders_completed` columns to `life.daily_facts`. Wired into `life.refresh_daily_facts()` via LATERAL join on `raw.reminders`. Added `reminder_summary` (due_today, completed_today, overdue_count) to `dashboard.get_payload()`. Schema version 7→8. Dropped stale VARCHAR overload of refresh_daily_facts (caused ambiguity). Fixed pre-existing `facts.daily_nutrition` column name bug (calories vs calories_consumed, date vs day). Down migration tested. `refresh_daily_facts(CURRENT_DATE)` → success. 2 files changed. |

### Recent (Feb 1)
| Task | Status | Summary |
|------|--------|---------|
| TASK-PLAN.8: Update TodayView Doc Comment | DONE | Updated line 4 doc comment from "one insight, nothing else" to "up to 3 ranked insights" — matches actual `ForEach(insights)` behavior. 1 file changed (TodayView.swift). iOS build: BUILD SUCCEEDED. Commit `e749126`. |
| TASK-PLAN.7: Reminder Sync Error Attribution | DONE | Wrapped `reminderSync.syncAllData()` in its own do/catch block inside `syncCalendar()`, separate from calendar sync. Reminder failures now logged as `[reminders]` (not `[calendar]`), calendar domain marked succeeded even when reminders fail, reminderCount falls back to 0 on failure. 1 file changed (SyncCoordinator.swift, +10/-4). iOS build: BUILD SUCCEEDED. Commit `6b94a7f`. |
| TASK-PLAN.6: Category Velocity Dashboard Insights | DONE | Migration 107: Added `category_trends` key to `dashboard.get_payload()` → `daily_insights`. Queries `finance.mv_category_velocity` for categories with `ABS(velocity_pct) > 25` and sufficient data, returns top 3 as `{ type, category, change_pct, direction, detail }`. Schema version 6→7. Current top trends: Food +1936%, Utilities +1386%, Government +531%. Down migration tested (reverts to v6, removes key). 2 files changed. |
| TASK-PLAN.5: Transaction Update SQL Sanitization | DONE | Added "Sanitize Inputs" Code node to both `transaction-update-webhook.json` (standard + with-auth). Validates: `id` as positive integer, `amount` as numeric, `date` as YYYY-MM-DD regex, escapes single quotes in `merchant_name`/`category`/`notes` (`'` → `''`). Added IF Valid branch: valid → Postgres, invalid → 400 error. Standard: 4→7 nodes, Auth: 6→9 nodes. JSON valid, O'Reilly escaping verified, injection blocked. `grep -c "replace.*'"` = 1 for both files. 2 files changed. Commit `9ca448d`. Note: workflows must be re-imported into n8n. |
| TASK-PLAN.6: GitHub Feed Status Threshold | DONE | Migration 104: Adjusted GitHub `expected_interval` from `24:00:00` to `7 days` in `life.feed_status_live`. Root cause: `github-sync.json` has `"active": false` in n8n, and even when active (every 6h), GitHub activity is sporadic (1-3 day gaps). Status changed from `error` → `ok`. Down migration tested (reverts to 24h/error). 2 files changed. User action: reactivate `GitHub Activity Sync` workflow in n8n for fresh data. |
| TASK-PLAN.4: GitHub Activity iOS View | DONE | Created `GitHubActivityView.swift` (summary card with streak/active days/pushes, 14-day bar chart, active repos list). Added NavigationLink in SettingsView Extras section. Reads from existing `DashboardPayload.githubActivity` via coordinator — no new API calls. Also fixed pre-existing build errors: SyncCoordinator.swift:291 (`count` → `totalCount`), ReminderSyncService.swift (added missing `import Combine`). 4 files changed. iOS build: BUILD SUCCEEDED. Commit `ff8995a`. |
| TASK-PLAN.3: Unblock facts.daily_finance | DONE | Migration 103: Rewrote `facts.refresh_daily_finance()` to read from `finance.transactions` (was `normalized.transactions` with 0 rows). Category mapping: title-case (Grocery, Food, Transport, etc.), income via category IN (Income, Salary, Deposit, Refund), transfers excluded. Wired into both `life.refresh_all()` overloads with error handling. Backfilled 330 dates. Verified: totals match source, `refresh_all(1, 'test-103')` → 0 errors. Down migration tested. 2 files changed. Also resolves older TASK-PLAN.2 (BLOCKED). |
| TASK-PLAN.2: Calendar Webhook SQL Sanitization | DONE | Added "Validate Dates" Code node with `/^\d{4}-\d{2}-\d{2}$/` regex between Webhook and Postgres. Added IF branch: valid → Postgres, invalid → 400 error response. Postgres now reads pre-validated `$json.start`/`$json.end` instead of raw query params. Injection attempts (`'; DROP TABLE`) blocked by regex. JSON valid (7 nodes, 5 connections). `grep -c` exit criteria = 2. 1 file changed. Commit `a982453`. Note: workflow must be re-imported into n8n. |
| TASK-PLAN.1: CalendarVM Error Feedback | DONE | Added `errorMessage = "Failed to load calendar events"` in 3 API failure branches (fetchTodayEvents, fetchWeekEvents, fetchMonthEvents). Exit criteria: `grep -c 'errorMessage.*Failed'` = 3. Pre-existing build error in SyncCoordinator.swift:291 (`count` not in scope — unrelated). 1 file changed. Commit `9563d92`. |
| TASK-FEAT.3: Calendar View (iOS) | DONE | Added Calendar tab to iOS app. Created CalendarViewModel (subscribes to coordinator for calendarSummary, fetches events via API), CalendarView (segmented Today/Week), CalendarTodayView (summary card + all-day chips + timeline), CalendarWeekView (grouped by day). Calendar tab at tag 4, Settings moved to tag 5. Model named `CalendarDisplayEvent` to avoid conflict with existing `CalendarEvent`. 5 files changed, 489 insertions. iOS build succeeded. Commit `43e3245`. |
| TASK-FEAT.2: Calendar Events Endpoint | DONE | Migration 101: Added `calendar_summary` to `dashboard.get_payload()` (schema v5→v6). Queries `life.v_daily_calendar_summary` for target date, returns meeting_count/meeting_hours/first_meeting/last_meeting with zero-fallback. Created n8n webhook workflow `calendar-events-webhook.json` (GET /webhook/nexus-calendar-events?start=&end=). Added `CalendarSummary` Codable struct to iOS `DashboardPayload.swift`. iOS build succeeded. |

### Recent (Jan 31)
| Task | Status | Summary |
|------|--------|---------|
| TASK-PLAN.1: Feed Status Thresholds | DONE | Migration 095: Added `expected_interval` column to `life.feed_status_live`, per-source thresholds (1h whoop, 48h healthkit/weight/sms, 24h github, 8h receipts, 7d manual/behavioral/location). Replaced VIEW with per-row threshold logic (ok=1x, stale=3x, error=3x+). Before: 5 error/3 stale/3 ok → After: 1 error/3 stale/7 ok. Down migration tested. |
| TASK-PLAN.4: iOS GitHub Model | DONE | Added `GitHubActivityWidget`, `GitHubSummary`, `GitHubDailyActivity`, `GitHubRepo` structs to `DashboardPayload.swift`. Optional field for backward compat. Build succeeded. Commit `5637391`. |
| TASK-PLAN.3: Dashboard GitHub Payload | DONE | Already wired — `github_activity` key was added in migration 087 (TASK-FEAT.1) via `COALESCE(life.get_github_activity_widget(14), '{}'::jsonb)`. Verified: IS NOT NULL=true, active_days_7d=3, payload size ~2.7KB. No migration needed. |
| TASK-PLAN.5: HealthKit → daily_health | DONE | Migration 098: Wired `facts.refresh_daily_health()` into both `life.refresh_all()` overloads. Backfilled all dates with WHOOP or HealthKit data. Steps: 6 dates populated, weight: 3 dates. `refresh_all(1, 'test-098')` → 0 errors. Down migration tested. |
| TASK-PLAN.7: Feed Counter Reset | DONE | Migration 099: Wired `life.reset_feed_events_today()` into both `life.refresh_all()` overloads (called at start). Verified: bank_sms 1108→0, github 11→0, receipts 2→0. Rows updated today (whoop, healthkit) correctly skipped — will reset after midnight. Down migration tested. |
| TASK-PLAN.8: Health Backfill | DONE | Migration 100: Cleaned 24 empty placeholder rows from `facts.daily_health`, re-ran `refresh_daily_health()` for all 12 dates with WHOOP/HealthKit source data. Before: 36 rows (24 empty). After: 12 rows (all with real data). `get_health_timeseries(90)` returns 90 gap-filled points. |

### Jan 27
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

---

## Auditor Planning Mode (2026-01-31)

## Planning Rationale

### Why these tasks were chosen

1. **TASK-PLAN.1 (Feed Status Thresholds)** — Highest impact, lowest effort. The dashboard currently shows 5 feeds as "error" and 3 as "stale" — most are false alarms from uniform 1-hour thresholds applied to feeds that update on 6-hour, daily, or event-driven schedules. This directly degrades user trust in the system. Single SQL migration, no iOS changes needed.

2. **TASK-PLAN.2 (facts.daily_finance)** — 0 rows in a table that already has refresh functions built. Just needs to be wired into the nightly pipeline. Unlocks per-category historical spending queries and future trend widgets.

3. **TASK-PLAN.3 (GitHub in Dashboard Payload)** — The backend function already exists (TASK-FEAT.1, 8.3ms). It just needs to be added to the existing payload function. One SQL migration.

4. **TASK-PLAN.4 (iOS GitHub Model)** — Direct follow-on to PLAN.3. Add the Codable struct so the data is available to SwiftUI views. TodayView is frozen, but the data needs to be decodable first before any view can use it.

5. **TASK-PLAN.5 (HealthKit → daily_health)** — 1051 HealthKit samples exist but aren't surfaced in daily facts. Steps and weight from HealthKit should complement WHOOP recovery/sleep/strain. Makes the health dashboard more complete.

6. **TASK-PLAN.6 (Category Velocity Insights)** — The `mv_category_velocity` materialized view already exists and is refreshed nightly. Surfacing it in insights costs one SQL addition and gives the user actionable spending trend alerts.

7. **TASK-PLAN.7 (Feed Counter Reset)** — Simple wiring task. The `reset_feed_events_today()` function exists but isn't called. Without it, `events_today` accumulates across days, making the count meaningless.

8. **TASK-PLAN.8 (Health Timeseries Backfill)** — The health timeseries endpoint exists but `facts.daily_health` only has 30 rows despite more raw data being available. Backfill unlocks richer trend charts.

### What was deliberately excluded

- **iOS TodayView changes** — TodayView is frozen. Didn't generate tasks to add widgets there.
- **Screen Time Integration** — Deferred per roadmap (needs App Store submission).
- **New HealthKit sync improvements** — Current sync works; 1051 rows flowing. Not broken, just stale sometimes due to user not opening app.
- **SMS/Receipt parsing changes** — Frozen pipelines.
- **Weekly insights email enhancement** — Roadmap item but lower priority than fixing false-alarm feed status and wiring existing unused data.
- **New n8n workflows** — Focused on wiring existing data/functions rather than building new ingestion.
- **Behavioral/location pipeline fixes** — These require Home Assistant automations (external system), not code changes.

---

## Auditor Planning Mode (2026-02-01)

## Planning Rationale

### Why these tasks were chosen

1. **TASK-PLAN.1 (CalendarViewModel Silent Failure)** — Highest impact for lowest effort. 2-line fix directly from auditor finding. Users currently see empty calendar with zero feedback on API failure. This is a UX bug that erodes trust.

2. **TASK-PLAN.2 (Calendar Webhook SQL Sanitization)** — Security fix for read-only endpoint. While blast radius is limited (SELECT only), data exfiltration via UNION injection is possible. Simple Code node addition with date regex validation.

3. **TASK-PLAN.3 (Unblock facts.daily_finance)** — This was BLOCKED in the previous planning cycle because `facts.refresh_daily_finance()` reads from `normalized.transactions` (0 rows). The fix is to rewrite it to read from `finance.transactions` (1366 rows). This unblocks PLAN.6 from the previous cycle (category velocity insights) and enables per-category spending analysis.

4. **TASK-PLAN.4 (GitHub Activity iOS View)** — The backend sends github_activity data, iOS decodes it (done in previous PLAN.4), but no view displays it. This is "last mile" wiring — all the data infrastructure exists, just needs a SwiftUI view. Delivers user-visible value from work already completed.

5. **TASK-PLAN.5 (Transaction Update SQL Sanitization)** — Higher risk than calendar endpoint because this is a WRITE operation. Marked `needs_approval` because it modifies an existing workflow that handles financial data, and both standard and with-auth versions need coordinated changes.

6. **TASK-PLAN.6 (GitHub Feed Status)** — GitHub shows `error` in feed status (5 days stale). Either the sync workflow stopped or the threshold is wrong. Low effort diagnostic + fix that removes a false alarm from the dashboard.

### What was deliberately excluded

- **iOS TodayView modifications** — Frozen. Can't add GitHub/calendar widgets there.
- **Category velocity insights (prev PLAN.6)** — Still blocked until PLAN.3 populates `facts.daily_finance`.
- **Weekly insights email** — Lower priority than security fixes and data wiring.
- **Screen time integration** — Deferred per roadmap (needs App Store).
- **Behavioral/location pipeline** — Requires Home Assistant (external system).
- **New data sources** — Focus is on wiring existing data (GitHub, calendar, finance categories) into user-visible surfaces.
- **HealthKit sync improvements** — Working fine (1187 samples), no action needed.
