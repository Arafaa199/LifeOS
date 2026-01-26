# Finance & Health Tab Redesign

## Overview

This document describes the redesigned Finance and Health tabs in the LifeOS iOS app. The goal is a premium, calm, decision-focused experience with clear hierarchy.

## Design Principles

1. **One Dashboard Per Tab** - No segmented controls or toggles between multiple views
2. **Max 8 Cards** - Reduces cognitive load, forces prioritization
3. **Clear Hierarchy** - Information flows from most important (today) to context (trends/insights)
4. **4-State Cards** - Every card handles: loading, empty, partial (stale), fresh
5. **Native iOS Feel** - System font, Dynamic Type, SF Symbols, 16pt spacing grid
6. **Decision-Focused** - Surface actionable information, not just data

---

## Finance Tab

### Hierarchy: Today → Month → Recent

| # | Card | Purpose | Priority |
|---|------|---------|----------|
| 1 | **Today Spend** (Hero) | Today's total spend with vs-yesterday delta | P0 - Hero metric |
| 2 | **Month Progress** | MTD spend with budget ring/gauge | P0 - Budget context |
| 3 | **Categories** | Top 3 spending categories with progress bars | P1 - Breakdown |
| 4 | **Quick Actions** | Expense, Income, Receipt buttons | P1 - Actions |
| 5 | **Recent** | Last 5 transactions, tap → full list | P1 - Activity |
| 6 | **Cashflow** | Income vs Expenses vs Net | P2 - Overview |
| 7 | **Insight** | Single most relevant insight | P2 - Intelligence |
| 8 | *(Reserved)* | Future expansion | - |

### Data Endpoint

```
GET /app/finance

Response: FinanceDashboardDTO
├── meta: { generatedAt, timezone, currency }
├── today: { spent, transactionCount, vsYesterday, isUnusual }
├── month: { spent, income, budget, budgetUsedPercent, daysRemaining, categories[] }
├── recent: FinanceTransactionDTO[]
└── insight: { type, title, detail, icon, severity }
```

### Card States

| State | Visual | Trigger |
|-------|--------|---------|
| Loading | Spinner, 60px min height | Initial load, no cache |
| Empty | Icon + "No data" message | API returns empty |
| Partial | Content + "15m ago" badge | Stale cache, refresh failing |
| Fresh | Content, no badge | Recent successful fetch |

### Currency & Timezone

- **Currency**: Always AED, formatted with `formatCurrency()` helper
- **Timezone**: Asia/Dubai for all transaction dates
- **Format**: "1,234.50 AED" (amount first, then currency code)

---

## Health Tab

### Hierarchy: Today → Trends → Insights

| # | Card | Purpose | Priority |
|---|------|---------|----------|
| 1 | **Recovery** (Hero) | Recovery ring + HRV/RHR/Strain | P0 - Hero metric |
| 2 | **Sleep** | Last night hours + efficiency + stages bar | P0 - Sleep |
| 3 | **Body** | Weight with 7d and 30d deltas | P1 - Body |
| 4 | **Activity** | Steps + Strain | P1 - Activity |
| 5 | **7-Day Trend** | Recovery sparkline | P2 - Context |
| 6 | **Insight** | Single cross-domain insight | P2 - Intelligence |
| 7-8 | *(Reserved)* | Future expansion | - |

### Data Endpoint

```
GET /app/health

Response: HealthDashboardDTO
├── meta: { generatedAt, timezone, dataCompleteness }
├── today: { recoveryScore, hrv, rhr, sleepMinutes, strain, steps, weightKg, ... }
├── trends: { recovery7d[], sleep7d[], avg7dRecovery, ... }
└── insight: { type, title, detail, icon, confidence, color }
```

### Recovery Color Coding

| Score | Color | Meaning |
|-------|-------|---------|
| 67-100 | Green | Good recovery, ready for strain |
| 34-66 | Yellow | Moderate, be mindful |
| 0-33 | Red | Low recovery, prioritize rest |

### Data Sources

- **WHOOP**: Recovery, HRV, RHR, Strain, Sleep (via Home Assistant integration)
- **HealthKit**: Steps, Weight (via iOS HealthKit)

Source badges (`SourceBadgeSmall`) indicate where each metric originates.

---

## Shared Components

### CardContainer

```swift
CardContainer(
    title: "Spending",
    icon: "creditcard",
    iconColor: .nexusFinance,
    isLoading: viewModel.isLoading,
    isEmpty: viewModel.isEmpty,
    staleMinutes: viewModel.staleMinutes,
    emptyMessage: "No transactions"
) {
    // Content
}
```

### SimpleCard

Basic styled container without state management:

```swift
SimpleCard {
    HStack {
        Text("Content")
        Spacer()
    }
}
```

### HeroCard

Elevated card for primary metrics:

```swift
HeroCard(accentColor: .nexusFinance) {
    VStack {
        Text("Today")
        Text("1,234 AED")
    }
}
```

### FreshnessBadge

Shows data age and offline status:

```swift
FreshnessBadge(
    lastUpdated: viewModel.lastUpdated,
    isOffline: viewModel.isOffline
)
```

### DeltaBadge

Shows percentage change with color coding:

```swift
DeltaBadge(12.5)                    // +12%
DeltaBadge(-8.3, suffix: " vs 7d")  // -8% vs 7d
DeltaBadge(15, invertColors: true)  // For spending (up = bad)
```

### ProgressRing

Circular progress indicator:

```swift
ProgressRing(
    progress: 0.72,      // 0-1
    color: .nexusFinance,
    lineWidth: 8,
    size: 70
)
```

### MiniSparkline

Simple line chart for trends:

```swift
MiniSparkline(
    data: [65, 72, 58, 80, 75, 82, 78],
    color: .nexusHealth,
    height: 40
)
```

---

## Interaction Model

### Navigation

| Action | Target |
|--------|--------|
| Pull down | Refresh data |
| Tap "See all" (Finance) | Full transaction list sheet |
| Tap transaction row | Transaction detail view |
| Tap gear icon (Finance) | Finance planning settings |
| Tap antenna icon (Health) | Health sources settings |

### Quick Actions

Finance tab has 3 quick actions:
- **Expense** → AddExpenseView sheet
- **Income** → IncomeView sheet
- **Receipt** → Receipt scanning (future)

### Drill-Down

Main tabs stay simple. Details are accessed via:
- Sheets (transactions list, settings)
- Navigation links (health sources)
- Tap on rows (transaction detail)

---

## File Structure

```
Nexus/
├── Components/
│   ├── DataState.swift           # DataState enum, Freshness enum
│   └── CardContainer.swift       # CardContainer, SimpleCard, HeroCard, etc.
├── Models/
│   ├── FinanceDashboardDTO.swift # Finance endpoint DTOs
│   └── HealthDashboardDTO.swift  # Health endpoint DTOs
├── ViewModels/
│   ├── FinanceDashboardViewModel.swift
│   └── HealthDashboardViewModel.swift
├── Views/
│   ├── Finance/
│   │   └── FinanceViewRedesign.swift
│   └── Health/
│       └── HealthViewRedesign.swift
└── docs/ui/
    └── finance_health_redesign.md  # This file
```

---

## Migration Path

The redesigned views are in separate files (`*Redesign.swift`) to allow parallel testing.

To switch to the new design:

1. In `NexusApp.swift` or the main TabView, replace:
   - `FinanceView()` → `FinanceViewRedesign()`
   - `HealthView()` → `HealthViewRedesign()`

2. Test all states (loading, empty, partial, fresh)

3. Once validated, the old views can be archived

---

## Backend Requirements

### New Endpoints Needed

The redesigned views expect unified endpoints. Currently they transform existing data, but ideally:

```sql
-- Finance endpoint should return:
GET /app/finance
{
  "meta": { "generated_at": "...", "timezone": "Asia/Dubai", "currency": "AED" },
  "today": { "spent": 287.50, "transaction_count": 4, "vs_yesterday": 15.2, "is_unusual": false },
  "month": { "spent": 4235.80, "income": 12500, "budget": 8000, ... },
  "recent": [...],
  "insight": { ... }
}

-- Health endpoint should return:
GET /app/health
{
  "meta": { "generated_at": "...", "timezone": "Asia/Dubai", "data_completeness": 0.85 },
  "today": { "recovery_score": 72, "hrv": 48, "sleep_minutes": 432, ... },
  "trends": { "recovery_7d": [...], "avg_7d_recovery": 72, ... },
  "insight": { ... }
}
```

The ViewModels include transformation logic to work with existing endpoints while the backend is updated.

---

## Testing Checklist

### Finance Tab
- [ ] Today spend shows correctly with AED formatting
- [ ] Budget ring shows correct percentage
- [ ] Categories show top 3 sorted by amount
- [ ] Quick actions open correct sheets
- [ ] Recent transactions show last 5
- [ ] "See all" opens full transaction list
- [ ] Pull-to-refresh works
- [ ] Offline state shows "Offline" badge
- [ ] Empty state shows when no data
- [ ] Insight card appears when relevant

### Health Tab
- [ ] Recovery ring shows correct color for score
- [ ] HRV/RHR/Strain display correctly
- [ ] Sleep hours and stages bar work
- [ ] Weight shows with deltas
- [ ] Steps/Strain activity row works
- [ ] 7-day sparkline renders
- [ ] Insight card shows with confidence badge
- [ ] WHOOP/HealthKit source badges display
- [ ] Pull-to-refresh works
- [ ] Empty state shows when no WHOOP connected

---

## Screenshots Instructions

After building the project, capture these screens:

1. **Finance Tab - Fresh Data**
   - Open Finance tab
   - Ensure data is loaded
   - Screenshot entire scroll view

2. **Finance Tab - Loading**
   - Kill app, clear cache
   - Reopen and screenshot immediately

3. **Health Tab - Normal Recovery**
   - Open Health tab with normal data
   - Screenshot entire scroll view

4. **Health Tab - Low Recovery**
   - If possible, on a low recovery day
   - Screenshot to show orange/red states

5. **Quick Action Sheet**
   - Tap "Expense" in Finance
   - Screenshot the sheet

---

*Document version: 1.0*
*Last updated: 2026-01-26*
