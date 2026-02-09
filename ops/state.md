# LifeOS — Canonical State
Last updated: 2026-02-09T16:25:00+04:00
Owner: Arafa
Control Mode: Autonomous (Human-in-the-loop on alerts only)

---

## OPERATIONAL STATUS

**System Version:** Operational v1
**Operational Start Date:** 2026-01-25
**TRUST-LOCKIN:** PASSED (verified 2026-01-25T16:02+04)
**Coder:** ENABLED (queue restocked 2026-02-04 — FEAT.11-17: Siri Shortcuts, HealthKit Medications, View Decomposition, Unit Tests, Streaks, Fasting Timer)
**Auditor:** STANDBY (will review new feature work)

### Current State
- Finance ingestion validated and complete (reimported 2026-02-04)
- SMS ingestion FIXED (intent-aware merchant extraction, 2026-02-04)
- All launchd services running (exit 0)
- WHOOP → normalized pipeline wired (migration 085)
- DB host: LAN IP (10.0.0.11) for all scripts
- iOS app: SyncCoordinator refactor complete (2026-01-27)
- n8n workflows deployed: reminders-sync, medications-batch, refresh-summary (2026-02-04)

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
| `Views/SettingsView.swift` | Decomposed from 482→212 lines; Sync Center, Debug, Config as separate files (2026-02-04) |

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

### normalized.* — DEPRECATED (Migration 135)
- Schema dropped. Pipeline is now: raw.whoop_* → life.daily_facts (direct)
- finance.v_daily_finance moved to finance schema
- Triggers write to raw only, no intermediate layer

### nutrition.* — EXPERIMENTAL
- Manual-entry only, low usage

---

## SMS INGESTION ARCHITECTURE

**Status:** ACTIVE (reimported 2026-02-04)

```
~/Library/Messages/chat.db
    ├── [fswatch] com.nexus.sms-watcher (instant)
    └── [cron] com.nexus.sms-import (every 15 min)
        └── import-sms-transactions.js
            ├── Reads: chat.db → filters bank senders
            ├── Classifies: sms-classifier.js + sms_regex_patterns.yaml (intent-aware)
            └── Writes: finance.transactions (DIRECT — bypasses raw layer)
```

SMS bypasses raw.bank_sms intentionally — idempotency via `external_id` UNIQUE on finance.transactions. Current stats (2026-02-04): 1336 transactions, 70.7% categorized, 4.6% missing merchant names. Merchant rules: 149 total.

---

## COMPLETED TASKS (Summary)

### Recent (Feb 2)
| Task | Status | Summary |
|------|--------|---------|
| TASK-PIPE.1: Fix WHOOP Propagation Triggers | DONE | Migration 124: Recreated 3 triggers with `AFTER INSERT OR UPDATE` (was INSERT only). Rewrote 3 trigger functions (`propagate_whoop_recovery/sleep/strain`) with nested BEGIN/EXCEPTION blocks — raw INSERT failure (due to raw.* immutability triggers) no longer blocks normalized layer updates. On raw failure, looks up existing raw_id. Verified: UPDATE on all 3 legacy tables propagates to normalized (updated_at refreshed). 0 trigger errors. Down migration tested (restores INSERT-only + original functions). 2 files changed. Commit `3e6f51f`. |
| TASK-PIPE.2: Backfill Normalized from Legacy | DONE | Migration 125: Touched all 36 legacy rows (12 recovery + 12 sleep + 12 strain) to re-fire PIPE.1 propagation triggers. Before: recovery 1 mismatch (27 vs 79), sleep 2 mismatches, strain 4 mismatches. After: all 3 parity checks return 0 rows. Rebuilt daily_facts for 397 days (2025-01-01 to 2026-02-01), all succeeded. 2 files changed. |
| TASK-PIPE.3: Deduplicate Raw WHOOP Tables | DONE | Migration 126: Dropped immutability triggers on raw.whoop_* (blocked DELETE/UPDATE). Deleted 1155 duplicate rows (466 cycles + 358 sleep + 331 strain — ~40x bloat). Replaced non-unique date DESC indexes with UNIQUE date indexes to prevent future duplication. Rewrote 3 propagation trigger functions to ON CONFLICT (date) DO UPDATE with correct column mappings (raw_json, run_id, millisecond columns for sleep, kilojoules/average_hr for strain, skin_temp_c for normalized recovery). Verified: 0 duplicates, all 6 tables at 12 rows, parity checks return 0 mismatches, trigger UPDATE test on all 3 legacy tables produces 0 errors and no new rows. 2 files changed. Commit `ea568e1`. |
| TASK-FEAT.4: Reminders Sync Webhook | DONE | Rewrote `reminders-sync-webhook.json` from 8-node ops.sync_runs pipeline to 4-node batch upsert pattern (matching healthkit-batch). Build SQL Code node constructs single batch INSERT with ON CONFLICT DO UPDATE, single-quote escaping. Removed `ops.start_sync`/`ops.finish_sync` (caused stuck 'running' rows). Handles empty payload gracefully. JSON valid (4 nodes, 3 connections). iOS build: BUILD SUCCEEDED. 1 file changed. Commit `a8f372f`. Note: workflow must be imported into n8n and activated. |
| TASK-FEAT.5: Reminders GET Endpoint | DONE | Rewrote `reminders-events-webhook.json` from 4-node workflow (no validation) to 7-node workflow with date validation. Added Validate Dates Code node (`/^\d{4}-\d{2}-\d{2}$/` regex), IF Valid branch, Respond Error (400). Postgres reads pre-validated `$json.start`/`$json.end`. Query includes incomplete reminders with no due date. Pattern matches calendar-events-webhook.json exactly. JSON valid (7 nodes, 5 connections). iOS build: BUILD SUCCEEDED. 1 file changed. Commit `acb12e7`. Note: workflow must be imported into n8n and activated. |
| TASK-FEAT.6: Calendar Month Summary View | DONE | Migration 109: Created `life.v_monthly_calendar_summary` VIEW aggregating `raw.calendar_events` by Dubai-timezone date. Columns: day, event_count, all_day_count, meeting_hours (non-all-day FILTER), has_events, first_event_time, last_event_time. Sparse output (12 days for Jan 2026 from 21 total events). All-day events tracked separately (meeting_hours NULL for all-day-only days). Down migration tested (DROP + re-CREATE). 2 files changed. |
| TASK-FEAT.7: Calendar + Productivity Correlation | DONE | Migration 110: Created `insights.calendar_productivity_correlation` VIEW joining calendar (meeting_count/hours), health (recovery, sleep, HRV, strain), productivity (GitHub push/PR/repos), and finance (spend_total) per day with prev/next day recovery. Meeting intensity: none/light/heavy/very_heavy (>2h threshold). Created `insights.calendar_pattern_summary()` function comparing 4 metrics across intensity buckets with significance findings. Fixed `insights.meetings_hrv_correlation` to use real calendar data (was all NULLs). 8 rows in correlation view, pattern summary correctly reports insufficient data for heavy meetings. Down migration tested. 2 files changed. Commit `27e9c53`. |
| TASK-FEAT.8: Reminder Daily Facts | DONE | Migration 111: Created `life.v_daily_reminder_summary` VIEW (per-day due/completed/overdue/completion_rate). Added `reminders_due` + `reminders_completed` columns to `life.daily_facts`. Wired into `life.refresh_daily_facts()` via LATERAL join on `raw.reminders`. Added `reminder_summary` (due_today, completed_today, overdue_count) to `dashboard.get_payload()`. Schema version 7→8. Dropped stale VARCHAR overload of refresh_daily_facts (caused ambiguity). Fixed pre-existing `facts.daily_nutrition` column name bug (calories vs calories_consumed, date vs day). Down migration tested. `refresh_daily_facts(CURRENT_DATE)` → success. 2 files changed. |
| TASK-FEAT.9: Calendar Background Sync | DONE | Added calendar + reminder sync to `syncForBackground()` in SyncCoordinator.swift. Guarded behind `calendarSyncEnabled` flag. Order: HealthKit push → Calendar/Reminder push → Dashboard fetch. `syncCalendar()` includes reminder sync with isolated error handling (PLAN.7). iOS build: BUILD SUCCEEDED. 1 file changed (SyncCoordinator.swift, +7/-2). |
| TASK-FEAT.10: Weekly Insights Email — Calendar + Reminders | DONE | Migration 112: Rewrote `insights.generate_weekly_markdown()` to include Calendar section (meetings, total hours, busiest day from `life.v_daily_calendar_summary`) and Reminders section (due, completed, overdue, completion rate from `life.v_daily_reminder_summary`). Added cross-domain insights: heavy meeting week (>10h) and low task completion (<50%) alerts. Verified: `store_weekly_report('2026-01-27')` → report includes Calendar (5 meetings, 4.0h, busiest Tue 27 Jan) and Reminders (no data yet). Down migration tested. 2 files changed. Commit `c34cc07`. |
| TASK-PIPE.4: Fix HRV Precision Loss | DONE | Migration 127: Widened 4 HRV columns from NUMERIC(5,1) to NUMERIC(6,2) — `raw.whoop_cycles.hrv`, `normalized.daily_recovery.hrv`, `facts.daily_health.hrv`, `facts.daily_summary.hrv`. Dropped/recreated `facts.v_daily_health_timeseries` (view dependency). Re-triggered propagation + rebuilt facts for all 12 dates. Before: 116.26→116.3 (precision loss). After: 116.26→116.26 (exact match). Parity check: 0 mismatches across full 5-table chain. Down migration tested. 2 files changed. Commit `4c95e2f`. |
| TASK-PIPE.5: Disable Coder and Signal Auditor Shutdown | DONE | All PIPE.1-4 pipeline fixes complete. Moved coder `.enabled` file to Trash (coder disabled). Created `auditor/.shutdown-after-audit` flag (auditor will shut down after next review cycle). macOS notification sent. Verified: coder `.enabled` absent, auditor shutdown flag present. 0 files changed (ops-only task). |

### Recent (Feb 6)
| Task | Status | Summary |
|------|--------|---------|
| TASK-PLAN.4: Budget Alert Push Notifications | DONE | Created NotificationManager.swift (118 LOC): requests notification authorization on first launch (stores flag in UserDefaults), sends UNNotification when budget exceeds 80% threshold, tracks `alertedBudgetsToday` Set to prevent spam (resets daily). Wired into SyncCoordinator.syncDashboard() → calls `checkBudgetAlerts(from:)` after network refresh. NexusApp.AppDelegate calls `requestNotificationPermissionIfNeeded()` on launch. 3 files changed (+137). Exit criteria: `grep -c 'UNUserNotificationCenter\|budgetAlert'` returns 3 (≥2 required). iOS build: BUILD SUCCEEDED. |
| TASK-PLAN.1: Offline Mode Indicator | DONE | Enhanced TodayBannersView: `TodayOfflineBanner` now shows queue count ("Offline — X items queued" with badge), added `TodaySyncingBanner` for online-with-pending state. TodayView observes `OfflineQueue.shared.pendingItemCount` via `@StateObject`. Banner order: Offline > Syncing > Cached > Stale. Exit criteria: `grep -c 'pendingCount\|TodaySyncingBanner'` returns 17 (≥2 required). 2 files changed (+77/-6). iOS build: BUILD SUCCEEDED. Commit `208060c`. |
| TASK-FEAT.17: Fasting Timer Display | DONE | Migration 152: Rewrote `health.get_fasting_status()` to query `nutrition.food_log` for last meal time — returns `hours_since_meal` and `last_meal_at` alongside explicit session. iOS: Updated `FastingStatus` with new fields + computed properties (`sinceMealFormatted`, `displayTimer`, `fastingGoalProgress`). Rewrote `FastingCardView` with progress ring (color changes at 75%/100%), passive "Since last meal" tracking, goal badges (16h/18h/20h appear when fasting 12+ hours). Schema version 12→13. 4 files changed. iOS build: BUILD SUCCEEDED. Down migration tested. |
| TASK-FEAT.16: Streak Tracking Widget | DONE | Backend already had streaks in dashboard payload (schema v12). Added iOS decode + display. Created `Streaks`, `StreakData` structs in DashboardPayload.swift with `sortedStreaks`, `bestActiveStreak`, `isAtBest` helpers. Created `StreakBadgesView.swift` (compact badges with icons, star for personal best, only shows when streaks active). Added to TodayView after StateCardView. 3 files changed (+208). Build: passes for streak files (pre-existing errors in WishlistView/DebtsListView unrelated). Commit `5c27cdb`. |
| TASK-FEAT.18: Fasting Timer Widget | DONE | **Already implemented in prior session.** Widget exists in `NexusWidgets.swift` (lines 418-728): `FastingTimerWidget` + `FastingWidgetProvider` + `FastingTimerWidgetView` with 4 size variants (small, medium, accessoryCircular, accessoryRectangular). SharedStorage has all fasting methods (lines 202-247). SyncCoordinator updates widget data after dashboard sync (lines 528-541). Features: progress ring toward goal, goal badges (16h/18h/20h), "Goal reached!" indicator, 15-min timeline updates. 0 files changed (already complete). iOS build: BUILD SUCCEEDED. |
| TASK-FEAT.19: Transaction Search | DONE | **Already implemented.** `FinanceActivityView.swift` has full search functionality: `@State private var searchText` (line 6), `filteredTransactions` computed property filters by merchant/category/notes (lines 16-46), `.searchable(text: $searchText, prompt: "Search transactions")` (line 176), category filter chips (lines 114-139), date range picker (lines 98-112). Uses native iOS `.searchable()` modifier which provides standard search bar UX with built-in debounce. 0 files changed (already complete). iOS build: BUILD SUCCEEDED. |
| TASK-FEAT.20: Subscription Monitor View | DONE | Created `SubscriptionsView.swift` (237 LOC): monthly total header, "Due Soon" section for items due within 7 days, all subscriptions list. Category-aware icons (TV for Netflix/Disney, music note for Spotify, etc.) and colors. Filters recurring items by monthly cadence OR subscription-like names. Added NavigationLink to SubscriptionsView in FinancePlanningView Recurring tab. 2 files changed (+251). iOS build: BUILD SUCCEEDED. Commit `0fdb9f1`. |
| TASK-FEAT.21: Error Boundary Views | DONE | Created `ErrorStateView.swift` (66 LOC) in new `Views/Components/` directory: warning triangle icon, configurable title/message, "Try Again" button with retry callback. Updated `TodayView.swift` to show error state when `errorMessage != nil && dashboardPayload == nil`. Updated `FinanceOverviewContent.swift` to show error state when `errorMessage != nil && hasNoData` (spent/income both 0 and no transactions). 3 files changed (+109/-31). iOS build: BUILD SUCCEEDED. Commit `c9409f7`. |

### Recent (Feb 9)
| Task | Status | Summary |
|------|--------|---------|
| TASK-PLAN.1: Fix Nightly Ops Runner | DONE | Replaced GNU `timeout` (not available on macOS) with `run_with_timeout()` function using `/usr/bin/perl -e 'alarm shift; exec @ARGV'`. Also fixed secondary stdin consumption bug — child scripts consumed the process substitution's fd, causing only 1 of 4 checks to run; fixed by adding `</dev/null`. Before: 4 checks × exit 127 (3+ days blind). After: smoke-tests PASS, schema-snapshot PASS, sms-replay FAIL (legitimate exit 1), ops-health-probe PASS. 1 file changed (ops/nightly.sh, +8/-1). Dry-run: 4 DRY RUN entries. Zero exit 127 in report. |

### Recent (Feb 7)
| Task | Status | Summary |
|------|--------|---------|
| TASK-PLAN.1: listening_events Migration | DONE | Migration 157: Formalized `life.listening_events` table (existed in prod but had no migration). Created `CREATE TABLE IF NOT EXISTS` with SERIAL PK, session_id UUID, track_title TEXT NOT NULL, artist, album, duration_sec, apple_music_id, started_at TIMESTAMPTZ NOT NULL, ended_at, source DEFAULT 'apple_music', raw_json JSONB, created_at. UNIQUE constraint on `(session_id, started_at)` for n8n idempotent inserts. Indexes: session_id, started_at DESC. Created `life.update_music_feed_status()` trigger function + `trg_listening_events_feed` AFTER INSERT trigger. Registered `music` source in `life.feed_status_live` with 24h expected_interval. Trigger test: insert → status changed from `unknown` to `ok` ✓. Down migration tested (drop + delete + re-apply). Migration tracked in `ops.schema_migrations`. 2 files created. iOS build: BUILD SUCCEEDED. |
| TASK-FEAT.26: Screen Time Integration | DONE | Migration 155: Created `life.screen_time_daily` table (date PK, total_minutes, category breakdown columns, pickups, first_pickup_at, raw_json). Added `screen_time_hours` NUMERIC(4,1) column to `life.daily_facts`. Created `life.update_daily_facts_screen_time(date)` function. Added `screen_time` feed status entry (48h expected_interval). Created `screen-time-webhook.json` n8n workflow: POST `/webhook/nexus-screen-time` with input validation (date format, total_minutes required), IF Valid branch, upsert + auto-update daily_facts + feed status. End-to-end test: 312 min → 5.2 hours ✓. 3 files created. iOS build: BUILD SUCCEEDED. |
| TASK-FEAT.27: Location Zone Improvement | DONE | Migration 156: Created `life.known_zones` table with 3 zones (Home, Fitness First Motor City, Dubai Sports City). Rewrote `get_location_type()` to query known_zones (was hardcoded with wrong coordinates — 25.0657 vs actual 25.0781621, 1.4km off). Rewrote `detect_location_zone()` to return zone NAME from known_zones. Rewrote `ingest_location()` to derive location_name from zone when HA sends 'unavailable'. Backfilled 128 records: location_type corrected (122 now 'home'), 109 'unavailable' names resolved to 'Home'. Before: 0 hours_at_home, 23 hours_away. After: 23 hours_at_home, 0 hours_away. daily_facts primary_location now 'home'. Down migration tested. 2 files changed. |
| TASK-FEAT.28: Recovery Lock Screen Widget | DONE | RecoveryScoreWidget already existed with `.systemSmall`, `.accessoryCircular`, `.accessoryRectangular`. SharedStorage already had recovery read/write. SyncCoordinator already synced recovery to widgets. Added `.accessoryInline` family support with "85% Recovery · HRV 116" format. Enhanced rectangular view to show HRV alongside recovery %. 1 file changed (NexusWidgets.swift, +24/-8). Both targets: BUILD SUCCEEDED. Commit `e2304c2`. |
| TASK-PLAN.2: Music Dashboard Summary | DONE | Migration 158: Created `life.v_daily_music_summary` VIEW (day, tracks_played, total_minutes, unique_artists, top_artist by frequency, top_album by frequency) using Dubai timezone. Added `music_today` key to `dashboard.get_payload()` with zero-value fallback for days without music data. Schema version 13→14. iOS: Added `MusicSummary` Codable struct (tracksPlayed, totalMinutes, uniqueArtists, topArtist, topAlbum) with `hasActivity` computed property. Added optional `musicToday` field to `DashboardPayload` with decode/encode support. Down migration tested (reverts to v13). 3 files changed. iOS build: BUILD SUCCEEDED. |
| TASK-PLAN.3: Calendar Replay Test | DONE | Created `ops/test/replay/calendar.sh` (149 LOC) with 4 checks: events-freshness (raw.calendar_events age — ok <48h, warn <168h, critical beyond), daily-summary (v_daily_calendar_summary has data in 30d), dashboard-payload (calendar_summary not null), reminders-table (raw.reminders queryable). JSON output mode with `--json` flag validated via `python3 -m json.tool`. `all.sh` auto-discovers calendar via `*.sh` glob (3 domains: calendar, finance, health). Currently reports critical for events-freshness (last sync Feb 4 — legitimate staleness). 1 file created. Commit `93b627a`. |
| TASK-PLAN.4: Fix Unknown Feed Triggers | DONE | Migration 159: Investigated all 3 "unknown" feed sources. Findings: `medications` trigger already existed (migration 140, just no data yet — iOS 18+ only), `music` trigger already existed (migration 157/PLAN.1, status already `ok`), `screen_time` had NO trigger on table (n8n webhook updated feed_status inline in SQL, but direct inserts skipped it). Created `life.update_feed_status_screen_time()` trigger function with ON CONFLICT upsert pattern. Created `trg_screen_time_feed_status` AFTER INSERT OR UPDATE on `life.screen_time_daily`. Test: INSERT → status `unknown`→`ok`, events_today=1. Upsert test → events_today incremented to 2. Down migration tested (drop trigger+function) and re-applied. 2 files created. |
| TASK-PLAN.5: Spending Anomaly Detection | DONE | Migration 161: Created `insights.detect_spending_anomaly(target_date)` — computes 30-day rolling avg from `facts.daily_finance`, returns JSONB for spending_spike (ratio >= 2.0, severity high) or spending_elevated (ratio >= 1.5, severity medium), NULL otherwise. Wired as Source 9 in `insights.get_ranked_insights()` with score 95/75. Tested: Jan 30 (1493 AED = 2.91x avg of 514) → spending_spike ranked #1; Jan 31 (145 AED) → NULL; today (no spending) → NULL. Dashboard payload confirmed working for both today and historical dates. Down migration tested (drops function, restores 8-source get_ranked_insights) and re-applied. 2 files created. |

### Recent (Feb 4)
| Task | Status | Summary |
|------|--------|---------|
| TASK-FIX.E2E: iOS End-to-End Sync Bugs | DONE | Fixed 3 interconnected iOS sync bugs plus 3 additional decode issues discovered during debugging. **Issue 1 (Dashboard ❌):** Swift expected `meta` nested object, backend sends flat `schema_version`/`generated_at`/`target_date`. Fix: Added custom `init(from decoder:)` to DashboardPayload that tries nested meta first, falls back to flat fields; added explicit `encode(to:)` for cache serialization. **Issue 2 (Health "no data"):** Cascaded from dashboard decode failure. Fix: Primary via Issue 1; also improved empty state messaging with context-aware icon/title/message (checks healthFreshness OR healthKitAuthorized). **Issue 3 (Documents error toast):** POST succeeded but refresh failed, both used same errorMessage. Fix: Separated POST success from refresh — optimistic local update, refresh in try/catch that logs but doesn't set errorMessage. Applied to createDocument/updateDocument/renewDocument. **Additional fixes found during debug:** (a) FeedHealthStatus: Added `.ok` case — backend sends `"status": "ok"`, Swift only had healthy/stale/critical/unknown. Updated all switch statements in HealthInsightsView, HealthSourcesView, SettingsView. (b) FeedStatus CodingKeys: Backend sends camelCase `lastSync`/`hoursSinceSync`, not snake_case. (c) **ROOT CAUSE** daily_insights type mismatch: Backend sends array `[{type,icon,...}]`, Swift expected struct with nested `rankedInsights`. Fix: Handle both formats in decoder, added DailyInsights convenience init. Evidence: `curl pivpn:5678/webhook/nexus-dashboard-today \| jq 'keys'` confirms flat structure. 5 files changed. iOS build: BUILD SUCCEEDED. |
| TASK-FEAT.13: TodayView Decomposition | DONE | Extracted TodayView (658→180 lines) into 7 focused card components: RecoveryCardView (109), BudgetCardView (80), NutritionCardView (72), FastingCardView (74), InsightsFeedView (96), StateCardView (96), TodayBannersView (97). Each component takes only the data it needs as parameters. TodayView now a clean composition. 8 files changed. iOS build: BUILD SUCCEEDED. Commit `ec2aa7c`. |
| TASK-FEAT.12: HealthKit Medications | DONE | Migration 140: Created `health.medications` table with idempotency on (medication_id, scheduled_date, scheduled_time, source). Added `health.v_daily_medications` view, `medications_today` to dashboard.get_payload() (schema v9→v10), feed status entry (48h interval). iOS: Added MedicationsSummary/MedicationDose Codable structs to DashboardPayload, MedicationDose struct + fetchMedicationDoses() to HealthKitManager (iOS 18+), syncMedications() to HealthKitSyncService wired into syncAllData(). Created medications-batch-webhook.json (n8n). 6 files changed (+672). iOS build: BUILD SUCCEEDED. Commit `9f32adb`. Note: n8n workflow must be imported and activated. |
| TASK-FEAT.11: Siri Shortcuts | DONE | Added 5 new App Intents (LogMoodIntent, LogWeightIntent, StartFastIntent, BreakFastIntent, enhanced LogWaterIntent) to `WidgetIntents.swift`. Updated `NexusAppShortcuts` provider with 7 total shortcuts. Replaced placeholder `SiriShortcutsView` with phrase examples UI. All intents use `ProvidesDialog` for confirmation, `openAppWhenRun: Bool = false` for background execution. 2 files changed (+315/-24). iOS build: BUILD SUCCEEDED. Commit `7a78eae`. |
| TASK-UI.1: Settings Reorganization | DONE | **Health Sources:** Moved toolbar button from HealthView to Settings "Data Sources" section (alongside GitHub Activity). **Finance refresh:** Removed redundant refresh button from FinanceView toolbar (pull-to-refresh already exists). **Debug section:** Added comprehensive Debug section to Settings with: API Debug Panel (existing), Dashboard Payload disclosure (meta, todayFacts, feed counts, insights), WHOOP Debug disclosure (raw sync timestamps, parsed dates, server status), Sync State disclosure (per-domain status, errors, staleness). Helper views: `dashboardDebugContent`, `syncStateDebugContent`, `debugRow`. 4 files changed (SettingsView +105, HealthView -7, FinanceView -6). iOS build: BUILD SUCCEEDED. |
| P1/P2 Trust Fixes | DONE | **P1-1:** Fixed DataSource always showing "network" in HealthViewModel and DashboardViewModel — now checks coordinator domain state for actual source. **P1-2:** Added `isFromCache` and `sourceLabel` computed properties to DomainState. **P1-3:** Created TodayCachedBanner component showing cache age. **P1-4:** Added "Cached" badge to Sync Center domain rows in SettingsView. **P2-1:** Added `isForToday` (Dubai timezone-aware day comparison) and `isDataOld` (>5 min threshold) to DashboardMeta. **Documents fix:** Separated POST success from refresh failure in create/update/renew. 11 iOS files changed. Commit `7fde022`. |
| SMS Parsing Improvements | DONE | **BER encoding fix:** Fixed `extractTextFromAttributedBody` to handle 0x81/0x82 length prefixes (long messages). **New patterns:** Added `funds_transfer_out_en` for outgoing fund transfers ("has been made using your Debit Card"), `salary_deposit_en` for English salary notifications with `category: "Salary"`. 2 files changed (import-sms-transactions.js, sms_regex_patterns.yaml). Commit `7fde022`. |
| Event-Driven Refresh | DONE | **Migration 141:** `trigger_refresh_on_write()` function for immediate daily_facts refresh. MVP on whoop_recovery. **Migration 142:** Coalescing queue pattern — `life.refresh_queue` table with (date, txid) key, `queue_refresh_on_write()` row trigger coalesces duplicates via ON CONFLICT, `process_refresh_queue()` statement trigger processes once per transaction. Applied to 5 source tables (whoop_recovery, whoop_sleep, whoop_strain, health.metrics, finance.transactions). Benefits: dashboard shows fresh data immediately, 100 rows = 1 refresh, exception-safe. 4 migration files + n8n workflow. Commit `9bb7e7d`. Migrations applied on nexus. |
| SMS Intent-Aware Merchant Fix | DONE | **Root cause:** `credit_transfer_local_in_via` pattern captured account number (To:4281) as merchant instead of sender name (From:SENDER). **Fix:** sms-classifier.js now uses intent-aware merchant extraction — income uses `from` field, expense uses `to/merchant`. Also fixed `online_purchase` pattern missing `At:` capture (243 transactions), `refund_pos` missing `At:` capture (9 transactions), classifier now uses `service`/`provider`/`biller` fields. Added 27 merchant rules for common patterns (subscriptions, groceries, BNPL, etc.). **Results:** Reimported 1336 SMS transactions, categorization rate improved from 39% → 70.7%. Data validated clean. 2 files changed. Commit `d6d6b66`. |
| TASK-FEAT.14: SettingsView Decomposition | DONE | Extracted SettingsView (482→212 lines) into 10 focused section components: SyncStatusSection (103), PipelineHealthSection (135), DomainTogglesSection (29), SyncIssuesSection (52), ConfigurationSection (59), DebugSection (199), SettingsRow (50), TestConnectionView (129), SiriShortcutsView (76), WidgetSettingsView (16). Per user instruction: NO manual refresh buttons on non-dev tabs — pull-to-refresh handles sync, Force Sync only in Debug section. SettingsView now a clean composition. 11 files changed (10 new + 1 modified). iOS build: BUILD SUCCEEDED. |

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
- DashboardPayload.swift decode logic (2026-02-04) — handles flat meta, camelCase FeedStatus, array daily_insights

---

## iOS ARCHITECTURAL IMPROVEMENTS (Completed 2026-02-03)

### Summary
Comprehensive iOS architecture audit completed across 3 phases. All critical issues resolved.

### Phase 1: ViewModel Lifecycle (COMPLETE)
- **FinanceView ViewModel leak** — Fixed by owning ViewModel in FinanceView instead of FinancePlanningView
- **API calls in Views** — Moved from HealthView, FinanceView to ViewModels
- **SyncCoordinator subscriptions** — Added domain-specific Combine publishers

### Phase 2: Data Flow (COMPLETE)
- **DashboardViewModel polling** — Replaced Task.sleep loop with Combine subscription to coordinator
- **Dead code removal** — Deleted FinanceViewRedesign.swift, HealthViewRedesign.swift (unused)
- **NetworkConfig singleton** — Centralized URL/timeout configuration

### Phase 3: Testability (COMPLETE)
- **Dependency Injection** — Added DI to ViewModels via init parameters
- **APIClientProtocol** — Exists in NexusAPI.swift, MockAPIClient ready for tests

### Remaining Tech Debt (P2/P3)
- TodayView (658 lines) — Extract cards → TASK-FEAT.13
- SettingsView (774 lines) — Extract sections → TASK-FEAT.14
- Unit tests foundation → TASK-FEAT.15

---

## AUDITOR PLANNING HISTORY

**2026-01-31 Cycle:** 8 PLAN tasks (Feed Status Thresholds, daily_finance, GitHub payload, iOS models, HealthKit daily_health, Category Velocity, Feed Counter Reset, Health Backfill) — ALL COMPLETE

**2026-02-01 Cycle:** 8 PLAN tasks (Calendar error feedback, SQL sanitization, daily_finance rewrite, GitHub iOS view, Transaction sanitization, GitHub feed threshold, Reminder error attribution, TodayView doc comment) — ALL COMPLETE

**2026-02-02 Cycle:** 5 PIPE tasks (WHOOP trigger events, Normalized backfill, Raw dedup, HRV precision, Coder shutdown) — ALL COMPLETE. 7 FEAT tasks (Reminders sync, Reminders GET, Calendar month, Calendar correlation, Reminder facts, Calendar background, Weekly email) — ALL COMPLETE

---

## Auditor Planning Mode (2026-02-06)

## Planning Rationale

### Why These Tasks Were Chosen

1. **TASK-PLAN.1 (Offline Indicator)** — High user value, low effort. Currently users have no visibility into whether their data is queued for sync. This causes confusion when network is spotty. Quick win from SUGG-14.

2. **TASK-PLAN.2 (Quick Actions)** — High user value, low effort. Builds on the Siri Shortcuts work (FEAT.11) but adds home screen convenience. iOS users expect 3D Touch quick actions. Quick win from SUGG-12.

3. **TASK-PLAN.3 (GitHub Sync)** — Critical data gap fix. The workflow has been inactive since Jan 27 (10 days of missing GitHub activity). This is a config-only change but marked `needs_approval` because it affects external API calls.

4. **TASK-PLAN.4 (Budget Alerts)** — Medium effort, high engagement value. Proactive notifications drive user retention. The budget logic already exists in `dashboard.get_payload()` — just needs to trigger a notification when threshold crossed.

5. **TASK-PLAN.5 (FinancePlanView)** — Quick polish. The view already exists (`FinancePlanningView.swift` is 27KB), but it's wired as a sheet from the gear button instead of inline in the tab. This unblocks the TODO on line 37.

### What Was Deliberately Excluded

- **Finance stub methods (debt, wishlist, cashflow)** — These require backend API endpoints that don't exist yet. Would be a multi-session effort.
- **HealthKit Medications full implementation** — Blocked on Apple's undocumented `HKMedicationDoseEventQueryDescriptor` API (iOS 18+).
- **Receipt→Nutrition matching (SUGG-06)** — High effort, requires ML/fuzzy matching research. Not a quick win.
- **Unit tests (SUGG-21)** — Blocked on Xcode target setup (requires user action).
- **Inactive n8n workflows (power-metrics, environment-metrics)** — These are intentionally disabled (IoT sensors not connected). Only GitHub sync is accidentally inactive.

### Task Ordering

1. **PLAN.1 + PLAN.2** are quick iOS-only wins with no backend changes
2. **PLAN.3** fixes a data gap that's been accumulating for 10 days
3. **PLAN.4 + PLAN.5** build on existing infrastructure with medium effort

---

## Auditor Planning Mode (2026-02-07)

## Planning Rationale

### Why These Tasks Were Chosen

1. **TASK-PLAN.1 (listening_events migration)** — **Critical infrastructure gap.** The table exists in prod but has no migration file. This means any environment rebuild (disaster recovery, staging) would break the music pipeline. The n8n workflow and iOS app are both fully implemented and waiting. Highest priority because it blocks PLAN.2 and fixes a reproducibility invariant.

2. **TASK-PLAN.2 (Music dashboard)** — **High user value, medium effort.** Music listening is the newest data source (FEAT.24), fully wired on iOS and n8n, but invisible in the dashboard. Adding it to the payload closes the loop and lets the user see their listening activity alongside recovery, spending, and other metrics.

3. **TASK-PLAN.3 (Calendar replay test)** — **Operational coverage.** Only 2 of 6+ domains have replay tests (33% coverage). Calendar is the newest active domain with real user data flowing. A replay test catches sync failures before the user notices stale calendar data.

4. **TASK-PLAN.4 (Fix unknown feeds)** — **Dashboard cleanliness.** Three "unknown" statuses in feed_status create noise — users can't tell if the system is healthy or broken. Ensuring triggers exist means the status will self-heal the moment data arrives.

5. **TASK-PLAN.5 (Spending anomaly)** — **Proactive user value.** The data already exists in `facts.daily_finance` (330 rows). A simple statistical comparison surfaces actionable insight ("You're spending 2.5x your daily average today") with no new data sources or pipelines.

6. **TASK-PLAN.6 (Nutrition replay test)** — **Test coverage for most-used feature.** Food/water logging is the most frequent user interaction. Regression testing ensures the calorie tracking pipeline doesn't silently break.

7. **TASK-PLAN.7 (Migration 155 hardening)** — **Low effort, fixes auditor finding.** Addresses the specific risk identified in the recent audit (missing BEGIN/COMMIT, missing schema_migrations cleanup). Advisory but important for reproducibility.

### What Was Deliberately Excluded

- **Debt/Wishlist implementation** — Requires both backend CRUD endpoints AND iOS views. Multi-session effort (3-4 sessions) that exceeds single-task scope. Better as a dedicated feature sprint.
- **Receipt→Nutrition matching (SUGG-06)** — High effort, needs fuzzy matching research. Not a quick win.
- **Apple Watch companion (SUGG-13)** — New target, significant effort, not aligned with current sprint priorities.
- **Data Export API (SUGG-17)** — No user request, speculative.
- **n8n README IP update** — Too trivial for a coder task, housekeeping only.

### Task Ordering Rationale

1. PLAN.1 first — unblocks PLAN.2 and PLAN.4 (music feed trigger)
2. PLAN.2 depends on PLAN.1 — music summary needs the table
3. PLAN.3 is independent — can run in parallel with PLAN.1/2
4. PLAN.4 after PLAN.1 — the music trigger from PLAN.1 is one of three feeds to fix
5. PLAN.5 is independent — pure backend function, no dependencies
6. PLAN.6 is independent — test infrastructure only
7. PLAN.7 is lowest priority — advisory, already-applied migration hardening

---

## Auditor Planning Mode (2026-02-09)

## Planning Rationale

### Why These Tasks Were Chosen

1. **TASK-PLAN.1 (Fix nightly runner)** — **Highest priority.** The ops monitoring infrastructure has been blind for 3+ days (Feb 6-8, all showing exit 127). Root cause: macOS launchd doesn't have GNU `timeout` in PATH. This is a 15-minute fix that restores visibility into all infrastructure checks. Without it, webhook failures, schema drift, and replay regressions go undetected.

2. **TASK-PLAN.2 (Create contracts)** — **Unblocks meaningful monitoring.** Even after PLAN.1 fixes `timeout`, `check.sh` iterates `ops/contracts/*.json` which doesn't exist — so all 16 webhook checks would either skip or fail differently. Creating the 5 most critical contracts means smoke tests actually validate API response shapes. Directly complements PLAN.1.

3. **TASK-PLAN.3 (BJJ in MoreView)** — **Quick win, high discoverability.** BJJ is fully implemented end-to-end (DB, n8n, iOS views) but hidden behind the dashboard card. Every other feature (Music, Supplements, Workouts, Documents, etc.) is accessible from MoreView. This is a 2-line change that makes the feature discoverable.

4. **TASK-PLAN.4 (BJJ in dashboard payload)** — **Performance fix.** Currently BJJCardView on TodayView fires a separate `HealthAPI.fetchBJJStreak()` call on every dashboard load. Wiring it into `dashboard.get_payload()` eliminates the extra round-trip and follows the established pattern (GitHub, Calendar, Reminders, Music all in payload).

5. **TASK-PLAN.5 (Supplements feed trigger)** — **Dashboard cleanliness.** `supplements` shows permanent "unknown" in Pipeline Health. The logging webhook exists and works, but no trigger updates feed_status_live. Same fix pattern used for screen_time (migration 159) and music (migration 157).

6. **TASK-PLAN.6 (BJJ feed status)** — **Completeness.** BJJ is the newest data domain with no feed status tracking. Adding it follows the pattern established for every other domain and ensures the Pipeline Health view is comprehensive.

### What Was Deliberately Excluded

- **Debt/Wishlist views** — Require both backend CRUD endpoints AND new iOS views. Multi-session effort that exceeds single-task scope. Better as a dedicated feature sprint.
- **Apple Watch companion** — New target, significant effort, not aligned with current sprint priorities.
- **Receipt→Nutrition matching improvement** — High effort, needs fuzzy matching research. Not a quick win.
- **Unit test expansion** — Blocked on Xcode target configuration (requires user action in Xcode GUI).
- **Health Score Composite (SUGG-05)** — Interesting but speculative. No user request driving it. Would need product design discussion.
- **Smart Hydration Reminders** — Requires Home Assistant automation + n8n workflow. Cross-system change that's better done in a dedicated session.

### Task Ordering Rationale

1. **PLAN.1 → PLAN.2**: Sequential dependency — fix the runner first, then give it contracts to validate against. Together they restore full monitoring coverage.
2. **PLAN.3**: Independent, iOS-only, 5 minutes. Quick win the coder can ship immediately.
3. **PLAN.4**: Backend + iOS change, medium effort. Reduces network calls on every dashboard load.
4. **PLAN.5 → PLAN.6**: Independent feed status triggers. Both follow established patterns, ~10 minutes each. Clean up the remaining "unknown" entries in Pipeline Health.
