# LifeOS Technical Documentation

> Comprehensive living technical reference for the LifeOS platform.
> For homelab infrastructure (network, devices, services), see `~/Cyber/Resources/Documentation/RFANW_Homelab.md`.
> Primary source of truth for all context: `~/CLAUDE.md`.

**Repository**: https://github.com/Arafaa199/LifeOS
**Local Path**: `~/Cyber/Dev/Projects/LifeOS/`

*Last Updated: 2026-02-08*

---

## Table of Contents

1. [Overview & Tech Stack](#1-overview--tech-stack)
2. [Database Architecture](#2-database-architecture)
3. [n8n API Reference](#3-n8n-api-reference)
4. [iOS App Architecture](#4-ios-app-architecture)
5. [Data Sources & Pipelines](#5-data-sources--pipelines)
6. [Finance System](#6-finance-system)
7. [CRUD Workflows](#7-crud-workflows)
8. [Claude Agents & Ops](#8-claude-agents--ops)
9. [Migration Log](#9-migration-log)
10. [Changelog](#10-changelog)

---

## 1. Overview & Tech Stack

### Monorepo Structure

```
~/Cyber/Dev/Projects/LifeOS/
├── ios/                          # iOS app (Swift/SwiftUI)
│   └── Nexus/                    # Xcode project
│       ├── Views/
│       │   ├── Dashboard/        # TodayView (canonical)
│       │   ├── Finance/          # FinanceView, FinancePlanningView, TransactionsListView, etc.
│       │   ├── Health/           # HealthView, HealthTrendsView, GitHubActivityView
│       │   ├── Calendar/         # CalendarView, CalendarWeekView, CalendarMonthView
│       │   ├── Documents/        # DocumentsListView, DocumentDetailView, DocumentFormView, RenewDocumentView
│       │   ├── Food/             # FoodLogView
│       │   ├── Nutrition/        # MealConfirmationView
│       │   ├── ContentView.swift
│       │   ├── SettingsView.swift
│       │   ├── SleepView.swift
│       │   ├── HistoryView.swift
│       │   ├── QuickLogView.swift
│       │   └── DebugView.swift
│       ├── ViewModels/           # DocumentsViewModel, etc.
│       ├── Models/               # FinanceModels, DocumentModels
│       └── Services/             # SyncCoordinator, NexusAPI, HealthKitManager, etc.
├── backend/
│   ├── migrations/               # PostgreSQL migrations (001-128)
│   ├── scripts/
│   │   ├── import-sms-transactions.js
│   │   ├── sms-classifier.js
│   │   ├── index-obsidian-vault.py
│   │   └── receipt-ingest/
│   │       ├── carrefour_parser.py
│   │       └── careem_parser.py
│   ├── n8n-workflows/            # ~60 workflow JSON exports
│   └── docs/                     # Historical design docs (contracts/, audit reports)
└── ops/                          # Claude agent orchestration
    ├── state.md                  # System state and evidence
    ├── queue.md                  # Task queue (milestone-prefixed IDs)
    ├── decisions.md              # Architectural Decision Log
    ├── alerts.md                 # Anomalies
    └── artifacts/
        ├── sql/                  # Additional SQL (051+)
        └── sms_regex_patterns.yaml
```

### Tech Stack

| Layer | Technology |
|-------|-----------|
| iOS App | Swift/SwiftUI, MVVM, Combine, HealthKit, EventKit |
| Database | PostgreSQL 16 (Docker on nexus) |
| Automation | n8n (Docker on pivpn) |
| Backend Scripts | Node.js (SMS import), Python (receipt parsing, vault indexing) |
| Infrastructure | nexus (DB), pivpn (n8n), pro14 (SMS import, agents) |

### Compatibility Symlinks

- `~/Cyber/Dev/Nexus-mobile` -> `Projects/LifeOS/ios`
- `~/Cyber/Dev/LifeOS-Ops` -> `Projects/LifeOS/ops`
- `~/Cyber/Infrastructure/Nexus-setup` -> `../Dev/Projects/LifeOS/backend`

---

## 2. Database Architecture

### Connection

- **Host**: `nexus` / `100.90.189.16`
- **Port**: `5432`
- **Database**: `nexus`
- **User**: `nexus`
- **Password**: In `/home/scrypt/nexus-setup/.env` on nexus

### Single-Pipeline Architecture (Migration 135)

```
Source → raw.* → life.daily_facts (dashboard)
                    ↑ life.refresh_daily_facts() reads raw.whoop_*, finance.v_daily_finance, raw.reminders
                    ↑ life.rebuild_daily_facts() = DELETE + recompute (deterministic)

normalized.* REMOVED (migration 135). facts.* DEPRECATED (migration 122).
life.refresh_all() calls only: life.refresh_daily_facts() + finance.refresh_financial_truth()
Migrations tracked in ops.schema_migrations. Run: backend/migrate.sh
```

### WHOOP Propagation Pipeline

```
n8n (15min poll) → health.whoop_recovery/sleep/strain (legacy, UPSERT)
                        ↓ AFTER INSERT OR UPDATE triggers (migration 135)
                   raw.whoop_cycles/sleep/strain (ON CONFLICT date DO UPDATE)
                        ↓
                   life.daily_facts (via life.refresh_daily_facts, ms→min conversion inline)
```

Triggers log errors to `ops.trigger_errors` + `RAISE WARNING` (never silent).

### Schema Hierarchy

#### `life.*` - Unified Event Model & Dashboard

| Table/View/Function | Purpose |
|---------------------|---------|
| `daily_facts` | Materialized daily metrics (recovery, sleep, weight, spending) |
| `documents` | Personal documents with expiry tracking (migration 128) |
| `document_reminders` | Junction: documents ↔ raw.reminders |
| `document_renewals` | Renewal audit trail |
| `v_documents_with_status` | Computed urgency (expired/critical/warning/ok) |
| `v_active_reminders` | Active reminders excluding soft-deleted (migration 117) |
| `v_daily_calendar_summary` | Calendar stats (meeting_count, meeting_hours) |
| `feed_status` | Data source health (ok/stale/error per source) |
| `locations` | Location events (arrival/departure/poll) |
| `daily_location_summary` | Time at home/away/work |
| `behavioral_events` | Sleep/wake detection, TV sessions |
| `daily_behavioral_summary` | TV hours, sleep detection times |
| `daily_productivity` | GitHub activity with health correlation |
| `refresh_daily_facts(date)` | Refresh for date (reads raw.whoop_*, finance.v_daily_finance) |
| `rebuild_daily_facts(start, end)` | Deterministic DELETE+recompute, audited |
| `refresh_all(days, caller)` | Calls refresh_daily_facts + refresh_financial_truth |
| `create_document_reminders(doc_id)` | Creates 4 reminders (30d, 7d, 5d, 1d before expiry) |
| `clear_document_reminders(doc_id)` | Marks reminders as deleted_local |
| `renew_document(doc_id, new_expiry, new_doc_number, notes)` | Atomic renewal with audit |
| `ingest_location(...)` | Ingest location event |
| `ingest_behavioral_event(...)` | Ingest behavioral event |

#### `raw.*` - Source Data

| Table | Purpose |
|-------|---------|
| `whoop_cycles` | WHOOP recovery (UNIQUE date, one row/day) |
| `whoop_sleep` | WHOOP sleep data |
| `whoop_strain` | WHOOP strain data |
| `healthkit_samples` | Apple Health readings |
| `bank_sms` | Raw bank SMS messages |
| `manual_entries` | Manual data entries |
| `github_events` | GitHub activity (synced 6h) |
| `calendar_events` | iOS EventKit events (migration 068) |
| `reminders` | Bidirectional Apple Reminders sync (migration 117) |
| `notes_index` | Obsidian vault metadata index (migration 118) |

**`raw.reminders` columns**: `sync_status`, `deleted_at`, `eventkit_modified_at`, `last_seen_at`, `origin`

#### `normalized.*` — REMOVED (Migration 135)

The normalized schema was removed. All pipelines now read directly from `raw.*` tables.
Finance aggregation moved to `finance.v_daily_finance` (VIEW over finance.transactions).
| `body_metrics` | Weight, body composition |
| `food_log` | Nutrition entries |
| `water_log` | Water intake |
| `mood_log` | Mood/energy ratings |

#### `facts.*` - DEPRECATED (migration 122)

Functions exist but are no longer called. Tables remain for historical data.

| Table | Content |
|-------|---------|
| `daily_health` | Aggregated daily health |
| `daily_nutrition` | Aggregated daily nutrition |
| `daily_finance` | Aggregated daily finance |
| `daily_summary` | Cross-domain daily summary |
| `daily_calorie_balance` | Energy deficit/surplus |
| `weekly_calorie_balance` | Weekly energy balance |
| `v_daily_health_timeseries` | Daily health metrics view |

**Legacy functions**: `facts.get_health_timeseries(days)` - still used for health timeseries API.

#### `finance.*` - Finance

| Table | Purpose |
|-------|---------|
| `transactions` | All transactions (SMS + manual), `transaction_at TIMESTAMPTZ` |
| `categories` | 16 default categories |
| `recurring_items` | Bills and recurring income |
| `merchant_rules` | Auto-categorization rules (120+) |
| `budgets` | Monthly budgets per category |
| `receipts` | Parsed receipt headers |
| `receipt_items` | Parsed receipt line items |

| View/Materialized View | Purpose |
|------------------------|---------|
| `v_timeline` | Unified timeline (bank_tx, refund, wallet_event, info) |
| `v_reconciliation_summary` | SMS capture rate, coverage score |
| `v_daily_spend_reconciliation` | Day-by-day comparison |
| `v_sms_ingestion_health` | Parse success by sender |
| `v_data_coverage_gaps` | Anomaly flagging (Z-score) |
| `v_receipt_transaction_matching` | Receipt-to-transaction matching |
| `v_dashboard_finance_summary` | iOS dashboard read-only summary |
| `receipt_ops_report` | Ops dashboard |
| `receipt_status_report` | Receipts by status |
| `mv_monthly_spend` | Monthly spending by category |
| `mv_category_velocity` | Spending trends |
| `mv_income_stability` | Income stability (CV%, rating) |
| `mv_spending_anomalies` | Z-score anomaly detection |

| Function | Purpose |
|----------|---------|
| `categorize_transaction()` | Trigger on INSERT/UPDATE, auto-categorize |
| `to_business_date(ts)` | Canonical date derivation (Asia/Dubai) |
| `current_business_date()` | Current date in Dubai timezone |
| `finalize_receipt(id)` | Atomic receipt finalization |
| `finalize_pending_receipts()` | Batch finalize pending |
| `refresh_financial_truth()` | Refresh all financial MVs |

#### `nutrition.*`

| View | Purpose |
|------|---------|
| `v_grocery_nutrition` | Receipt items → nutrition data (pg_trgm fuzzy match) |

#### `ops.*` - Operational Audit

| Table | Purpose |
|-------|---------|
| `refresh_log` | Per-day refresh audit trail |
| `rebuild_runs` | Rebuild audit trail (migration 123) |
| `trigger_errors` | Trigger failure log |

#### `insights.*` - Cross-Domain Correlation

| Table | Purpose |
|-------|---------|
| `sleep_recovery_correlation` | Sleep vs next-day recovery |
| `spending_recovery_correlation` | Spending vs recovery |
| `screen_sleep_correlation` | TV time vs sleep quality |
| `productivity_recovery_correlation` | GitHub vs recovery |
| `daily_anomalies` | Z-score anomaly detection |
| `cross_domain_alerts` | Multi-domain alert patterns |
| `pattern_detector` | Day-of-week behavioral patterns |

### Canonical Day Boundary

**Timezone: Asia/Dubai (UTC+4)**

```sql
SELECT finance.to_business_date(transaction_at) AS business_date;
-- Equivalent: (transaction_at AT TIME ZONE 'Asia/Dubai')::date
-- Midnight boundary: 20:00 UTC = midnight Dubai
```

---

## 3. n8n API Reference

n8n runs on pivpn (Docker). All webhooks at `https://n8n.rfanw/webhook/<path>`.

**Postgres Credential ID**: `p5cyLWCZ9Db6GiiQ`
**Email Service**: `http://172.17.0.1:8025/send-email` (Docker gateway IP)
**API Key**: In `~/Cyber/Infrastructure/Nexus-setup/.env`
**Webhook v2 Note**: Nodes using "Respond to Webhook" require `responseMode: "responseNode"`

### Health

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/webhook/nexus-sleep?date=X` | WHOOP sleep/recovery for date |
| GET | `/webhook/nexus-sleep-history?days=7` | Sleep history |
| GET | `/webhook/nexus-health-timeseries?days=30` | Daily health time series |
| POST | `/webhook/nexus-weight` | Log weight (HealthKit sync) |
| POST | `/webhook/nexus-mood` | Log mood/energy (1-10) |
| POST | `/webhook/nexus-workout` | Log workout |

### Nutrition

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/webhook/nexus-food` | Food logging (voice/text/photo) |
| POST | `/webhook/nexus-water` | Water intake |

### Finance

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/webhook/nexus-expense` | Quick expense ("coffee 15 AED") |
| POST | `/webhook/nexus-transaction` | Add transaction (client_id) |
| GET | `/webhook/nexus-finance-summary` | Finance overview |
| GET | `/webhook/nexus-budgets` | Budget list |
| GET | `/webhook/nexus-monthly-trends` | Monthly trends |
| POST | `/webhook/nexus-income` | Add income (client_id) |
| POST | `/webhook/nexus-update-transaction` | Update transaction |
| DELETE | `/webhook/nexus-delete-transaction/:id?id=X` | Delete transaction |
| POST | `/webhook/nexus-refresh-summary` | Refresh summaries (after SMS import) |

### Finance Planning

| Method | Path | Purpose |
|--------|------|---------|
| GET/POST | `/webhook/nexus-categories` | CRUD categories |
| GET/POST | `/webhook/nexus-recurring` | CRUD recurring items |
| GET/POST | `/webhook/nexus-rules` | CRUD matching rules |

### Dashboard

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/webhook/nexus-dashboard-today` | Unified dashboard payload |

### Receipts

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/webhook/nexus-receipt-ingest` | Ingest receipt (pdf_hash required) |

### Reminders (Bidirectional Sync)

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/webhook/nexus-reminders-sync` | Diff-aware upsert from iOS (eventkit_modified_at echo-back) |
| GET | `/webhook/nexus-reminders?start=X&end=X` | Fetch reminders for date range |
| GET | `/webhook/nexus-reminders-sync-state` | All active + pending_push rows |
| POST | `/webhook/nexus-reminder-create` | Create from Nexus/MCP (pending_push) |
| POST | `/webhook/nexus-reminder-update` | Update, sets pending_push |
| POST | `/webhook/nexus-reminder-delete` | Soft delete |
| POST | `/webhook/nexus-reminder-confirm-sync` | iOS confirms EventKit write |

### Documents (Migration 128)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/webhook/nexus-documents` | List documents (with computed status) |
| POST | `/webhook/nexus-document-create` | Create document + auto-create reminders |
| POST | `/webhook/nexus-document-update` | Update document fields |
| POST | `/webhook/nexus-document-delete` | Soft delete + clear reminders |
| POST | `/webhook/nexus-document-renew` | Renew with new expiry + audit trail |

### Notes (Obsidian Indexing)

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/webhook/nexus-notes-index` | Batch upsert vault metadata |
| GET | `/webhook/nexus-notes-search?q=X` | Search by title/tags/frontmatter |

### Behavioral Signals

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/webhook/nexus-location` | Location event (lat, lon, event_type) |
| POST | `/webhook/nexus-behavioral-event` | Behavioral event (sleep_detected, etc.) |

### Scheduled Workflows (Cron)

| Workflow | Schedule | Purpose |
|----------|----------|---------|
| health-metrics-sync | Every 15 min | Poll HA for WHOOP → health.metrics |
| carrefour-gmail-automation | Every 6h | Gmail → PDF → Carrefour receipt |
| careem-email-automation | Every 6h | Gmail → HTML → Careem receipt (ID: L0ILJivki7LaRBjk) |
| github-sync | Every 6h | GitHub API → raw.github_events |
| weekly-insights-report | Sunday 8am | Weekly insights email |
| nightly-refresh-facts | Nightly | Facts rebuild |
| cleanup-stale-events | Every 5 min | Mark stuck pending events as failed |

---

## 4. iOS App Architecture

**Path**: `~/Cyber/Dev/Projects/LifeOS/ios/Nexus/`
**Language**: Swift/SwiftUI
**Pattern**: MVVM with Combine
**External Dependencies**: None (pure Swift)

### Key Services

| Service | Purpose |
|---------|---------|
| `SyncCoordinator.swift` | Singleton, owns ALL sync (dashboard, finance, healthKit, calendar) |
| `NexusAPI.swift` | API client for n8n webhooks |
| `HealthKitManager.swift` | Read weight/steps/calories from Apple Health |
| `HealthKitSyncService.swift` | Sync HealthKit data to backend |
| `BackgroundTaskManager.swift` | Background refresh scheduling |
| `OfflineQueue.swift` | Offline-first with client_id idempotency |
| `DashboardService.swift` | Dashboard data fetching |
| `ReminderSyncService.swift` | 6-step bidirectional diff engine for Apple Reminders |
| `CalendarSyncService.swift` | Calendar sync with EventKit |
| `CacheManager.swift` | Local caching |
| `NetworkMonitor.swift` | Connectivity monitoring |
| `PhotoFoodLogger.swift` | Photo-based food logging |
| `SpeechRecognizer.swift` | Voice input transcription |

### SyncCoordinator (Single Sync Spine)

- Singleton `SyncCoordinator.shared` owns ALL sync across 4 domains
- `syncAll(force:)` runs domains in parallel via TaskGroup, 15s debounce
- `NexusApp.onChange(.active)` → `SyncCoordinator.shared.syncAll()` (single entry point)
- ViewModels subscribe via Combine:
  - `DashboardViewModel` → `$dashboardPayload`
  - `HealthViewModel` → `$dashboardPayload`
  - `FinanceViewModel` → `$financeSummaryResult`

### Key Views

| View | Location | Purpose |
|------|----------|---------|
| `TodayView.swift` | Dashboard/ | CANONICAL dashboard (frozen Jan 2026) |
| `FinanceView.swift` | Finance/ | Finance tab with spending overview |
| `FinancePlanningView.swift` | Finance/ | Categories, Recurring, Rules settings |
| `TransactionsListView.swift` | Finance/ | Transaction list with filters |
| `CalendarView.swift` | Calendar/ | Calendar with week/month/year views |
| `DocumentsListView.swift` | Documents/ | Document expiry tracking |
| `DocumentFormView.swift` | Documents/ | Create/edit documents |
| `RenewDocumentView.swift` | Documents/ | Document renewal flow |
| `HealthView.swift` | Health/ | Health metrics display |
| `SleepView.swift` | (root) | Sleep data view |
| `FoodLogView.swift` | Food/ | Food logging |
| `SettingsView.swift` | (root) | Settings + Sync Center |
| `ContentView.swift` | (root) | Tab bar container |

### Dashboard (Frozen Jan 2026)

`TodayView.swift` is the CANONICAL dashboard (247 lines):
- Recovery ring (green >66%, yellow 34-66%, red <34%)
- Spend status (normal/high/unusual based on `spendUnusual` + `spendVs7d`)
- Single insight card (prioritized: unusual spending → low recovery → high recovery)
- No charts, no customization, no toggles

### Settings - Sync Center

- "Sync Now (All)" triggers all 4 domains
- Per-domain rows: status dot, last sync time, errors
- Cache age + "Force Refresh (bypass cache)"
- Clear Local Data

### Reminder Sync (Bidirectional)

`ReminderSyncService.swift` - 6-step diff engine:
1. Pull EventKit reminders
2. Pull DB reminders (`nexus-reminders-sync-state`)
3. Diff (compare by eventkit_modified_at)
4. Handle absence (missing from EventKit = deleted)
5. Push changes to DB (`nexus-reminders-sync`)
6. Confirm sync (`nexus-reminder-confirm-sync`)

Loop prevention via `eventkit_modified_at` echo-back.

### Documents CRUD (Migration 128)

- **Tab**: Documents (6th tab, between Calendar and Settings)
- `DocumentsListView` shows documents grouped by status (expired, critical, warning, ok)
- `DocumentFormView` for create/edit with doc_type picker (passport, visa, ID, etc.)
- `DocumentDetailView` with renewal history navigation (shows `DocumentRenewalHistoryView`)
- `RenewDocumentView` for renewal with new expiry date
- Auto-creates 4 reminders in Apple Reminders via `life.create_document_reminders()`
- Integrated with SyncCoordinator (`.documents` domain, synced in Phase 2)
- n8n webhooks: `nexus-documents` (GET), `nexus-document` (POST/DELETE), `nexus-document-update` (POST), `nexus-document-renew` (POST), `nexus-document-recreate-reminders` (POST), `nexus-document-renewals` (GET)

### Privacy Permissions (Info.plist)

| Key | Purpose |
|-----|---------|
| `NSMicrophoneUsageDescription` | Voice input for food/expense logging |
| `NSSpeechRecognitionUsageDescription` | Speech transcription |
| `NSHealthShareUsageDescription` | Read HealthKit data |
| `NSHealthUpdateUsageDescription` | Write HealthKit data |
| `NSRemindersFullAccessUsageDescription` | Bidirectional reminder sync |

---

## 5. Data Sources & Pipelines

### Source Table

| Source | Path | Storage | Refresh |
|--------|------|---------|---------|
| WHOOP (HRV, sleep, recovery, strain) | HA HACS → n8n poll | health.whoop_* → raw.whoop_* → life.daily_facts | 15 min |
| Weight (Eufy scale) | HealthKit → iOS → webhook | health.metrics | On app open |
| Steps/Calories (Apple Watch) | HealthKit → iOS | Local display only | On app open |
| Bank SMS | chat.db → fswatch → import script | finance.transactions | Instant (fswatch) + 15min fallback |
| Receipts (Carrefour) | Gmail PDF → n8n → parser | finance.receipts + receipt_items | 6h cron |
| Receipts (Careem) | Gmail HTML → n8n → parser | finance.receipts + receipt_items | 6h cron |
| GitHub activity | GitHub API → n8n | raw.github_events | 6h cron |
| HA behavioral signals | HA automations → webhook | life.behavioral_events, life.locations | Event-driven |
| Obsidian notes | index-obsidian-vault.py | raw.notes_index | Manual / scheduled |
| iOS Calendar | EventKit → CalendarSyncService | raw.calendar_events | On app open |
| Apple Reminders | EventKit ↔ ReminderSyncService | raw.reminders (bidirectional) | On app open |

### WHOOP Data Flow

```
WHOOP Cloud → HA (HACS whoop) → n8n (health-metrics-sync, 15min)
  → health.whoop_recovery/sleep/strain (UPSERT)
  → TRIGGER → raw.whoop_cycles/sleep/strain (ms→min conversion inline)
  → life.daily_facts (via refresh_daily_facts)
```

### SMS Import Pipeline

```
Bank SMS → Messages (chat.db) → fswatch trigger → import-sms-transactions.js
  → sms-classifier.js (+ sms_regex_patterns.yaml) → finance.transactions
  → categorize_transaction() trigger → auto-categorize
```

**Launchd**: `com.nexus.sms-watcher` (fswatch), `com.nexus.sms-import` (15min fallback)

### Receipt Pipeline

```
Gmail → n8n cron (6h) → carrefour_parser.py / careem_parser.py
  → POST /webhook/nexus-receipt-ingest (pdf_hash dedup)
  → finance.receipts + finance.receipt_items
```

**Parsers**: `backend/scripts/receipt-ingest/`
**Gmail Labels**: `LifeOS/Receipts/Carrefour`, `LifeOS/Receipts/Careem`

---

## 6. Finance System

### Core Tables

| Table | Key Columns |
|-------|-------------|
| `finance.transactions` | `id`, `transaction_at TIMESTAMPTZ`, `merchant_name`, `amount`, `currency`, `category`, `client_id UUID`, `match_rule_id`, `match_reason`, `match_confidence` |
| `finance.categories` | `id`, `name`, `is_expense` (16 defaults) |
| `finance.recurring_items` | `id`, `name`, `amount`, `frequency`, `category_id` |
| `finance.merchant_rules` | `id`, `pattern`, `category`, `priority` (120+ rules) |
| `finance.budgets` | `id`, `category_id`, `monthly_limit`, `month` |
| `finance.receipts` | `id`, `vendor`, `total`, `pdf_hash`, `status`, `transaction_id` |
| `finance.receipt_items` | `id`, `receipt_id`, `name`, `qty`, `unit_price`, `total` |

### Timezone Handling

- `transaction_at TIMESTAMPTZ` stores when the transaction occurred
- `finance.to_business_date(ts)` = `(ts AT TIME ZONE 'Asia/Dubai')::date`
- Business date boundary: 20:00 UTC = midnight Dubai

### Auto-Categorization

Trigger `categorize_transaction()` on INSERT/UPDATE:
1. Match `merchant_name` against `merchant_rules.pattern` (120+ rules)
2. Set `category`, `match_rule_id`, `match_reason`, `match_confidence`
3. Fallback: "Uncategorized" with `match_reason='no_match'`

### Idempotency

- `client_id UUID` generated by iOS
- `UNIQUE INDEX idx_transactions_client_id WHERE client_id IS NOT NULL`
- n8n: `ON CONFLICT (client_id) DO NOTHING`

### SMS Coverage (Audited Jan 2026)

| Metric | Value |
|--------|-------|
| Pattern Coverage | 99% (343 SMS, 1 unhandled) |
| Capture Rate | 92.9% |
| Banks | EmiratesNBD (Arabic), AlRajhiBank, JKB, CAREEM, Amazon |
| Intents | FIN_TXN_APPROVED, FIN_TXN_REFUND, FIN_TXN_DECLINED, IGNORE, FIN_INFO_ONLY, FIN_AUTH_CODE |

### SMS Dedup

`SHA256(sender|amount|merchant|date)` - same hash within 24h = duplicate, after 24h = new (recurring).

### Receipt Matching

Receipts linked to SMS transactions by: merchant (fuzzy) + amount (exact) + date (plus/minus 1 day). Receipts are secondary data enriching existing transactions.

### Reconciliation Views

| View | Purpose |
|------|---------|
| `v_reconciliation_summary` | SMS capture rate, coverage score |
| `v_daily_spend_reconciliation` | Day-by-day comparison |
| `v_sms_ingestion_health` | Parse success by sender |
| `v_data_coverage_gaps` | Z-score anomaly flagging |
| `v_receipt_transaction_matching` | Receipt-transaction match confidence |

---

## 7. CRUD Workflows

### Documents

```
iOS DocumentFormView → POST /webhook/nexus-document
  → INSERT life.documents
  → life.create_document_reminders(doc_id)
    → INSERT raw.reminders (4 rows, sync_status='pending_push')
  → RESPONSE {id, status}

iOS ReminderSyncService (next sync)
  → GET /webhook/nexus-reminders-sync-state
  → finds pending_push reminders
  → creates in EventKit
  → POST /webhook/nexus-reminder-confirm-sync
```

**Renewal**:
```
iOS RenewDocumentView → POST /webhook/nexus-document-renew
  → life.renew_document(doc_id, new_expiry, new_doc_number, notes)
    → INSERT life.document_renewals (audit)
    → UPDATE life.documents (new expiry)
    → life.clear_document_reminders(doc_id) (old)
    → life.create_document_reminders(doc_id) (new)
```

**Renewal History**:
```
iOS DocumentDetailView → NavigationLink to DocumentRenewalHistoryView
  → GET /webhook/nexus-document-renewals?id=X
  → SELECT * FROM life.document_renewals WHERE document_id = X
  → Shows old→new expiry, doc number changes, notes, timestamps
```

### Transactions

**SMS Import**:
```
chat.db change → fswatch → import-sms-transactions.js
  → sms-classifier.js (parse + classify intent)
  → INSERT finance.transactions (ON CONFLICT sms_hash DO NOTHING)
  → categorize_transaction() trigger fires
  → POST /webhook/nexus-refresh-summary
```

**Manual**:
```
iOS → POST /webhook/nexus-transaction {amount, merchant, category, client_id}
  → INSERT finance.transactions (ON CONFLICT client_id DO NOTHING)
  → categorize_transaction() trigger fires
```

### Receipts

```
n8n cron (6h) → Gmail API → find new emails with label
  → carrefour_parser.py / careem_parser.py
  → POST /webhook/nexus-receipt-ingest {vendor, items, totals, pdf_hash}
  → INSERT finance.receipts (ON CONFLICT pdf_hash DO NOTHING)
  → INSERT finance.receipt_items
```

### Reminders (Bidirectional)

**iOS → DB** (on app open):
```
ReminderSyncService.syncAll()
  → Read EventKit reminders
  → GET /webhook/nexus-reminders-sync-state
  → Diff: new/updated/deleted
  → POST /webhook/nexus-reminders-sync {reminders[]}
    → UPSERT raw.reminders (eventkit_modified_at echo-back)
```

**DB → iOS** (pending_push):
```
POST /webhook/nexus-reminder-create → INSERT raw.reminders (sync_status='pending_push')
  → Next iOS sync picks up pending_push rows
  → Creates in EventKit
  → POST /webhook/nexus-reminder-confirm-sync {reminder_id, eventkit_modified_at}
```

### Food/Water/Mood

```
iOS → POST /webhook/nexus-food-log {description, calories, protein, carbs, fat, client_id}
  → INSERT nutrition.food_log (normalized.food_log removed in migration 135)
iOS → POST /webhook/nexus-water {amount_ml, client_id}
  → (water_log not yet implemented — normalized table was always empty)
iOS → POST /webhook/nexus-mood {score, energy, notes}
  → (mood_log not yet implemented — normalized table was always empty)
```

---

## 8. Claude Agents & Ops

### Agent Architecture

Three Claude-powered agents on pro14 via launchd:

| Agent | Schedule | Purpose | Model |
|-------|----------|---------|-------|
| Coder | Every 9 min | Execute topmost task from queue.md | Sonnet |
| Auditor | Every 35 min | Review commits, PASS/BLOCK verdict | Opus |
| SysAdmin | Nightly 22:15 | Read-only health check, all hosts | Sonnet |

**Agent Home**: `~/Cyber/Infrastructure/ClaudeAgents/`
**Management**: `manage.sh` (enable/disable/status/run/logs)

### LifeOS-Ops Workflow

```
Orchestrator adds task → queue.md
  → Coder picks up topmost READY task
  → Implements, commits to main, logs evidence to state.md
  → Auditor reviews recent commits
  → Issues PASS or BLOCK
  → If BLOCK: Coder fixes before next task
```

### Milestone Roadmap

| Milestone | Goal | Status |
|-----------|------|--------|
| M0 | System Trust - data correct, replayable | IN PROGRESS |
| M1 | Daily Financial Truth | ACTIVE |
| M2 | Behavioral Signals - zero manual input | BLOCKED |
| M3 | Health x Life Join | BLOCKED |
| M4 | Productivity Signals | DEFERRED |
| M5 | iOS App Validation | DEFERRED |
| M6 | Autonomous Intelligence | FUTURE |

### Auditor Block Criteria

Data loss, duplication, silent failure, inconsistent state, credential exposure, AI output treated as truth without confidence scoring.

### Key Aliases

```bash
agents-status          # All agents
cc-on/off/status/run/logs/state   # Coder
cca-on/off/status/run/findings    # Auditor
csa-on/off/status/run/findings    # SysAdmin
lo-status / lo-queue / lo-state   # LifeOS-Ops
```

---

## 9. Migration Log

| # | Description | Date |
|---|-------------|------|
| 001-002 | Merchant rules, recategorization | Jan 2026 |
| 003-006 | Schema creation: raw, normalized, facts, life | Jan 2026 |
| 007-008 | SMS date quarantine | Jan 2026 |
| 009 | Finance idempotency (client_id) | Jan 2026 |
| 010 | Finance planning (categories, recurring, rules, triggers) | Jan 2026 |
| 011 | Timezone consistency (TIMESTAMPTZ, to_business_date) | Jan 2026 |
| 012, 018-021 | Receipt ingestion system | Jan 2026 |
| 022 | Financial truth layer (materialized views) | Jan 2026 |
| 023-024 | Location tracking + behavioral events | Jan 2026 |
| 025 | Calorie balance | Jan 2026 |
| 026 | GitHub activity | Jan 2026 |
| 027-028 | Correlation views + cross-domain anomalies | Jan 2026 |
| 029-031 | Finance daily/MTD views, budget status, dashboard function | Jan 2026 |
| 032-037 | Ops pipeline health, feeds status, confidence, ingestion gaps | Jan 2026 |
| 038 | Finance budget engine | Jan 2026 |
| 039 | Source trust scores | Jan 2026 |
| 040-042 | Daily life summary, finance canonical, anomaly explanations | Jan 2026 |
| 043-045 | Sleep/spend correlation, SMS intents, screen/sleep, workload/health | Jan 2026 |
| 046-047 | Daily coverage, client_id constraint fix | Jan 2026 |
| 060-064 | Coverage audit, SMS intent enum, raw events, timeline, daily summary | Jan 2026 |
| 067-075 | Grocery nutrition, calendar, healthkit, coverage, meal inference, continuity | Jan 2026 |
| 077-080 | Health timeseries, dashboard weight, receipt brands, nutrition ingredients | Jan 2026 |
| 081-094 | Sync runs, dashboard insights, quality gates, freshness, WHOOP normalization | Jan 2026 |
| 111 | Reminder daily facts | Jan 2026 |
| 112 | Weekly report calendar reminders | Jan 2026 |
| 113 | Fix receipt feed threshold | Jan 2026 |
| 117 | Reminders bidirectional sync | Feb 2026 |
| 118 | Notes index (Obsidian vault metadata) | Feb 2026 |
| 119 | Normalized finance view (no ETL) | Feb 2026 |
| 120 | Rewire daily_facts to read ONLY normalized | Feb 2026 |
| 121 | Fix silent trigger failures | Feb 2026 |
| 122 | Deprecate competing pipeline (facts.*) | Feb 2026 |
| 123 | Deterministic rebuild (DELETE+recompute, audited) | Feb 2026 |
| 124 | Fix WHOOP trigger events | Feb 2026 |
| 125 | Backfill normalized from legacy | Feb 2026 |
| 126 | Dedup raw WHOOP | Feb 2026 |
| 127 | Fix HRV precision | Feb 2026 |
| **128** | **Documents & Expiry tracking** (life.documents, reminders, renewals) | **Feb 2026** |
| 129-134 | FX pairing, non-economic exclusion, recurring due advance, nutrition DB, Dubai TZ | Feb 2026 |
| **135** | **Deprecate normalized schema** — pipeline now raw → life.daily_facts | **Feb 2026** |
| **136** | **ops.schema_migrations** tracking table + backend/migrate.sh | **Feb 2026** |
| 137-146 | iOS NexusTheme, enhanced intents, haptic feedback, error handling | Feb 2026 |
| 147-150 | Music listening events, daily_facts music/fasting columns, explain_today | Feb 2026 |
| 151-166 | Trust hardening, receipts nutrition linking, reminder sync fixes | Feb 2026 |
| **167** | **Receipt auto-matching** — trigram search, 98.2% match rate | **Feb 2026** |
| **168** | **Refresh queue background-poll redesign** — fixes txid race condition | **Feb 2026** |
| **169** | **Data integrity constraints** — NULL-safe unique indexes, ON DELETE RESTRICT | **Feb 2026** |
| 170-172 | Calendar+medications combined view, reminder/medication toggle webhooks | Feb 2026 |
| 173 | Weight fallback in dashboard, fix v_daily_mood_summary view | Feb 2026 |
| 174 | Align finance with actuals — Tabby Credit, recurring items, Feb budgets | Feb 2026 |
| 175 | January cleanup — Grocery→Groceries, Uncategorized→Salary | Feb 2026 |
| **176** | **Financial position** — account_balances, v_upcoming_payments, auto-reconciliation | **Feb 2026** |

---

## 10. Changelog

Append-only. Agents and humans add entries after changes.

### 2026-02-08 - Financial Position & Auto-Reconciliation (Migration 174-176)

- Added `finance.account_balances` table for current balances
- Added `finance.v_upcoming_payments` unified view (recurring + installments)
- Added `finance.get_financial_position()` function returning JSONB
- Added `finance.reconcile_payment()` trigger for auto-matching transactions
- Created iOS `FinancialPositionView.swift` with net worth, accounts, upcoming payments
- Created `FinanceQuickCard.swift` for dashboard summary
- n8n workflows: `financial-position-webhook.json`, `weekly-bills-notification.json`
- Documentation cleanup: archived outdated `Overall_Setup.md`

### 2026-02-07 - NexusTheme UI Overhaul (Migration 137-150)

- Created unified `NexusTheme.swift` design system
- Updated 89 files with consistent theming
- Added haptic feedback across key interactions
- Music listening events pipeline (Apple Music → Postgres)
- `explain_today` daily briefing with data gap awareness
- Trust hardening: fixed silent failures across ViewModels

### 2026-02-03 - Normalized Schema Removal (Migration 135-136)

- Dropped `normalized` schema entirely — 9 tables + 1 view + 1 function
- Pipeline simplified: `raw.whoop_* → life.daily_facts` (no intermediate)
- `finance.v_daily_finance` moved from `normalized` to `finance` schema
- Triggers rewritten to write raw only (removed normalized INSERT)
- Added `calories_active` column to `raw.whoop_strain`
- Created `ops.schema_migrations` tracking table
- Created `backend/migrate.sh` — migration runner (status, baseline, run, pending)
- All 115 existing migrations baselined

### 2026-02-02 - Documentation Reorganization

- Created this document (LifeOS_Technical_Documentation.md) as the living technical reference
- Merged Technical_Bible.md + Overall_Setup.md into RFANW_Homelab.md
- Retired stale backend/docs/ (LIFEOS-ARCHITECTURE.md, DATA-PIPELINE-ARCHITECTURE.md, README.md)

### 2026-02-01 - Documents & Expiry (Migration 128)

- Added `life.documents`, `life.document_reminders`, `life.document_renewals` tables
- Added `life.v_documents_with_status` view with urgency computation
- Added iOS views: DocumentsListView, DocumentDetailView, DocumentFormView, RenewDocumentView
- Auto-creates 4 reminders (30d, 7d, 5d, 1d before expiry) in Apple Reminders

### 2026-02-01 - Single-Pipeline Consolidation (Migrations 117-127)

- Reminders bidirectional sync (migration 117)
- Obsidian notes indexing (migration 118)
- Replaced 3-tier pipeline with single pipeline: raw → normalized → life.daily_facts (normalized later removed in migration 135)
- Deprecated facts.* layer (migration 122)
- Deterministic rebuild with audit trail (migration 123)
- WHOOP trigger propagation (migration 124)
- HRV precision fix (migration 127)

### 2026-01-15 - Finance System Maturity

- Receipt parsing: Carrefour (PDF) + Careem (HTML)
- Reconciliation views for SMS coverage analysis
- Financial materialized views (monthly spend, anomalies, income stability)
- SMS coverage audited: 99% pattern coverage, 92.9% capture rate

### 2026-01-10 - iOS SyncCoordinator

- Replaced scattered sync logic with SyncCoordinator singleton
- 4 domains synced in parallel (dashboard, finance, healthKit, calendar)
- Frozen TodayView dashboard design
- Added Finance Planning UI (categories, recurring, rules)
- Added Sync Center in Settings

---

*Source of truth: `~/CLAUDE.md` > this document > `LifeOS/ops/*` > `RFANW_Homelab.md`*
