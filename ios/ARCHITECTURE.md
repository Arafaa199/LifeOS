# iOS Architecture — LifeOS/Nexus

Ground truth for all iOS development. Read this before touching any file.

---

## Directory Layout

```
ios/Nexus/
├── NexusApp.swift                    # @main entry, scenePhase → SyncCoordinator
├── Constants.swift                   # App-wide constants
├── DesignSystem.swift                # DO NOT TOUCH — colors, modifiers, components
│
├── Components/
│   ├── CardContainer.swift           # CardContainer, SimpleCard, HeroCard, FreshnessBadge, ProgressRing
│   └── DataState.swift               # Generic loading/error/empty state enum
│
├── Models/
│   ├── DashboardPayload.swift        # All Codable structs for dashboard JSON
│   ├── NexusModels.swift             # Core response types (NexusResponse, SleepResponse, etc.)
│   ├── FinanceModels.swift           # Finance types (Category, RecurringItem, MatchingRule, etc.)
│   ├── APIClientProtocol.swift       # Protocol for testable API client
│   └── ErrorHandlingViews.swift      # Error display components
│
├── Services/
│   ├── SyncCoordinator.swift         # CENTRAL — owns all sync, ViewModels subscribe via Combine
│   ├── NexusAPI.swift                # Network layer — all webhook calls
│   ├── DashboardService.swift        # Cache layer for dashboard payload
│   ├── CacheManager.swift            # Generic disk cache
│   ├── CalendarSyncService.swift     # EventKit → webhook (push only, no display view yet)
│   ├── HealthKitManager.swift        # Apple Health read/write
│   ├── HealthKitSyncService.swift    # HealthKit → webhook push
│   ├── BackgroundTaskManager.swift   # BGTaskScheduler registration
│   ├── OfflineQueue.swift            # Offline retry with OSAllocatedUnfairLock
│   ├── NetworkMonitor.swift          # NWPathMonitor wrapper
│   ├── PhotoFoodLogger.swift         # Camera → food logging
│   ├── SpeechRecognizer.swift        # Voice → text
│   ├── SharedStorage.swift           # App Group UserDefaults (widgets)
│   └── AppSettings.swift             # @AppStorage toggles (per-domain sync enable)
│
├── Utilities/
│   ├── ColorHelper.swift             # Color conversion helpers
│   └── TimeFormatter.swift           # Date/time formatting
│
├── ViewModels/
│   ├── DashboardViewModel.swift      # Subscribes to coordinator.$dashboardPayload
│   └── FinanceViewModel.swift        # Subscribes to coordinator.$financeSummaryResult
│
├── Views/
│   ├── ContentView.swift             # TabView with 5 tabs
│   ├── SettingsView.swift            # Settings + Sync Center
│   ├── QuickLogView.swift            # Food/water/mood/expense quick entry
│   ├── DebugView.swift               # Debug info
│   ├── HistoryView.swift             # History browser
│   ├── SleepView.swift               # Sleep detail
│   ├── Dashboard/
│   │   └── TodayView.swift           # DO NOT TOUCH — frozen canonical dashboard
│   ├── Health/
│   │   ├── HealthView.swift          # Segmented: Today/Trends/Insights + HealthViewModel
│   │   ├── HealthTodayView.swift     # Today's health metrics
│   │   ├── HealthTrendsView.swift    # Charts and trends
│   │   ├── HealthInsightsView.swift  # AI-generated health insights
│   │   ├── HealthSourcesView.swift   # Data source status
│   │   └── HealthViewRedesign.swift  # Experimental redesign
│   ├── Finance/
│   │   ├── FinanceView.swift         # Main finance tab
│   │   ├── FinanceViewRedesign.swift # Experimental redesign
│   │   ├── FinancePlanningView.swift # Categories/Recurring/Rules settings
│   │   ├── FinanceActivityView.swift # Transaction list
│   │   ├── FinanceBudgetsView.swift  # Budget management
│   │   ├── FinanceComponents.swift   # Shared finance UI components
│   │   ├── AddExpenseView.swift      # Manual expense entry
│   │   ├── QuickExpenseView.swift    # Quick expense
│   │   ├── IncomeView.swift          # Income entry
│   │   ├── TransactionsListView.swift # Transaction list view
│   │   ├── TransactionDetailView.swift # Single transaction detail
│   │   ├── DateRangeFilterView.swift # Date picker filter
│   │   ├── MonthlyTrendsView.swift   # Monthly spending trends
│   │   ├── SpendingChartsView.swift  # Spending charts
│   │   ├── InsightsView.swift        # Finance insights
│   │   ├── InstallmentsView.swift    # Installment tracking
│   │   └── BudgetSettingsView.swift  # Budget settings
│   ├── Food/
│   │   └── FoodLogView.swift         # Food logging with voice/photo
│   └── Nutrition/
│       └── MealConfirmationView.swift # Meal confirmation
│
└── Widgets/
    ├── NexusWidgets.swift            # Widget definitions
    ├── InteractiveWaterWidget.swift   # Water tracking widget
    └── WidgetIntents.swift           # Widget intent handlers
```

---

## Data Flow

```
NexusApp.swift
  └── .onChange(.active) → SyncCoordinator.shared.syncAll(force: true)

SyncCoordinator (singleton)
  ├── Phase 1 — PUSH (TaskGroup, parallel)
  │   ├── syncHealthKit()     — if AppSettings.healthKitSyncEnabled
  │   └── syncCalendar()      — if AppSettings.calendarSyncEnabled
  │
  └── Phase 2 — PULL (TaskGroup, parallel)
      ├── syncDashboard()     — always → publishes $dashboardPayload
      ├── syncFinance()       — if AppSettings.financeSyncEnabled → publishes $financeSummaryResult
      └── syncWHOOP()         — if AppSettings.whoopSyncEnabled

ViewModels subscribe via Combine:
  DashboardViewModel  → coordinator.$dashboardPayload
  HealthViewModel     → coordinator.$dashboardPayload (+ direct API for timeseries)
  FinanceViewModel    → coordinator.$financeSummaryResult
```

---

## SyncCoordinator

**File:** `Services/SyncCoordinator.swift`
**Singleton:** `SyncCoordinator.shared`

### Domains
```swift
enum SyncDomain: String, CaseIterable {
    case dashboard, finance, healthKit, calendar, whoop
}
```

### Key Published Properties
- `domainStates: [SyncDomain: DomainState]` — per-domain sync status
- `dashboardPayload: DashboardPayload?` — main dashboard data
- `financeSummaryResult: FinanceResponse?` — finance summary
- `isSyncingAll: Bool` — global sync indicator

### Debounce
`syncAll()` has a 15-second minimum interval. `syncAll(force: true)` bypasses.

---

## How to Add a Feature (Checklist)

Use HealthView as the reference pattern.

### Step 1: Model (if new data)
- Add Codable structs to `Models/DashboardPayload.swift` (if from dashboard payload)
- Or add to `Models/NexusModels.swift` (if standalone endpoint)
- Make new fields **optional** (`?`) for backward compatibility

### Step 2: API Endpoint (if new webhook)
- Add method to `Services/NexusAPI.swift`
- Use existing `get<T>()` or `post<Body, Response>()` helpers
- Follow pattern: `func fetchThing() async throws -> ThingResponse`

### Step 3: ViewModel
- Create `ViewModels/FeatureViewModel.swift`
- `@MainActor class FeatureViewModel: ObservableObject`
- Subscribe to coordinator via Combine in `init()`:
  ```swift
  coordinator.$dashboardPayload
      .compactMap { $0 }
      .receive(on: DispatchQueue.main)
      .sink { [weak self] payload in self?.update(payload) }
      .store(in: &cancellables)
  ```
- Forward `coordinator.objectWillChange` for loading state reactivity

### Step 4: Views
- Create `Views/Feature/FeatureView.swift` — top-level with segmented picker
- Create sub-views for each segment (e.g., `FeatureTodayView.swift`)
- Use `NavigationView` wrapper, `.navigationTitle()`, `.navigationBarTitleDisplayMode(.large)`
- Use `@StateObject private var viewModel = FeatureViewModel()`
- Trigger data load: `.task { await viewModel.loadData() }`

### Step 5: Tab Registration
- Add tab in `Views/ContentView.swift`:
  ```swift
  FeatureView()
      .tabItem { Label("Feature", systemImage: "icon") }
      .tag(N)  // Next available tag number
  ```

### Step 6: Wire to SyncCoordinator (if new sync domain)
- Add case to `SyncDomain` enum
- Add sync method in Phase 1 (push) or Phase 2 (pull)
- Add `@Published` property for data
- Add `AppSettings` toggle if needed

### Step 7: Build & Verify
```bash
xcodebuild -scheme Nexus -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20
```

---

## Design System

**File:** `DesignSystem.swift` — DO NOT MODIFY

### Colors
| Token | Usage |
|-------|-------|
| `.nexusPrimary` | Brand cyan, tint, links |
| `.nexusAccent` | Coral, destructive/attention actions |
| `.nexusHealth` / `.nexusFinance` / `.nexusFood` / `.nexusWater` / `.nexusMood` | Domain colors |
| `.nexusSuccess` / `.nexusWarning` / `.nexusError` | Semantic status |
| `.nexusCardBackground` | Card surface (systemGray6) |
| `.nexusCardBackgroundElevated` | Elevated card surface (systemGray5) |

### View Modifiers
| Modifier | Usage |
|----------|-------|
| `.nexusCard()` | Standard card (padding + bg + corner 16 + shadow) |
| `.nexusCard(elevated: true)` | Elevated card variant |
| `.nexusGlassCard()` | Frosted glass effect (ultraThinMaterial + corner 20) |
| `.nexusPrimaryButton()` | Full-width primary CTA |
| `.nexusSecondaryButton()` | Full-width secondary CTA |
| `.nexusAccentButton()` | Full-width accent CTA |
| `.nexusChip(color:)` | Small pill badge |
| `.nexusTextField()` | Styled text input |

### Reusable Components
| Component | Purpose |
|-----------|---------|
| `CardContainer` | Stateful card (loading/empty/partial/fresh) with title + icon |
| `SimpleCard` | Plain styled container |
| `HeroCard` | Large primary metric display |
| `FreshnessBadge` | Sync freshness indicator (green/orange/red dot) |
| `ProgressRing` | Circular progress (used for recovery score) |
| `NexusSegmentedPicker` | Custom segmented control |
| `NexusStatCard` | Icon + value + unit + optional trend |
| `NexusEmptyState` | Empty state with icon + message + optional action |
| `NexusHeaderView` | Section header with icon |

### Spacing Convention
No formal spacing tokens. Common values: 4, 8, 12, 16, 20, 32. Use 16 as default padding.

---

## API Pattern

**File:** `Services/NexusAPI.swift`
**Singleton:** `NexusAPI.shared`
**Base URL:** Configured via Settings (default: `https://n8n.rfanw`)

### Adding an Endpoint
```swift
// GET endpoint
func fetchCalendarEvents(start: Date, end: Date) async throws -> CalendarEventsResponse {
    let fmt = ISO8601DateFormatter()
    let s = fmt.string(from: start)
    let e = fmt.string(from: end)
    return try await get("/webhook/nexus-calendar-events?start=\(s)&end=\(e)")
}

// POST endpoint
func logSomething(_ data: SomePayload) async throws -> NexusResponse {
    return try await post("/webhook/nexus-something", body: data)
}
```

All `URLRequest`s have `timeoutInterval = 30`.

---

## Tab Inventory

| Tag | View | Label | Icon | ViewModel |
|-----|------|-------|------|-----------|
| 0 | `TodayView` | Home | `house` | DashboardViewModel (env object) |
| 1 | `QuickLogView` | Log | `plus.circle` | DashboardViewModel (env object) |
| 2 | `HealthView` | Health | `heart` | HealthViewModel (local @StateObject) |
| 3 | `FinanceView` | Finance | `chart.pie` | FinanceViewModel (local @StateObject) |
| 4 | `SettingsView` | Settings | `gearshape` | N/A |

**Next available tag: 5**

---

## DO NOT TOUCH

These are frozen and must not be modified without explicit owner approval:

| File/Area | Reason |
|-----------|--------|
| `DesignSystem.swift` | User-customized design tokens |
| `Dashboard/TodayView.swift` | Frozen canonical dashboard (247 lines) |
| SMS import pipeline | `backend/scripts/import-sms-transactions.js`, `sms-classifier.js` |
| Receipt parsing | `backend/scripts/receipt-ingest/` |
| WHOOP sensor mappings | HA → n8n → health.whoop_* |
| Core transaction schema | `finance.transactions` columns |

---

## Existing Infrastructure (Calendar)

`CalendarSyncService.swift` already exists and handles **push** (iOS EventKit → webhook):
- Syncs last 30 days + next 7 days of calendar events
- Posts to `/webhook/nexus-calendar-sync`
- Registered as `.calendar` domain in SyncCoordinator (Phase 1 push)
- Data lands in `raw.calendar_events` on the server

**What's missing:**
- No **pull** endpoint to fetch events for display
- No CalendarViewModel
- No CalendarView (no display UI)
- Calendar summary stats not in dashboard payload
- The `life.v_daily_calendar_summary` view exists server-side (migration 068) with `meeting_count` and `meeting_hours`

---

## Build Command

```bash
cd ~/Cyber/Dev/Projects/LifeOS/ios
xcodebuild -scheme Nexus -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20
```

Xcode 15+, iOS 17+ deployment target.
