# Finance Tab Redesign - Smoke Test Checklist

**Date**: 2026-01-25
**Version**: v1.0

---

## Structure Changes

### Before
- 5 sub-tabs: Quick, History, Budget, BNPL, Insights
- Custom icon tab bar

### After
- 3 segments: Overview, Activity, Budgets
- Standard iOS segmented control
- BNPL and Insights moved to standalone views (accessible via links if needed)

---

## Smoke Test Checklist

### Overview Screen
- [ ] MTD Spend displays in AED (not $)
- [ ] Budget status badge shows percentage correctly
- [ ] Progress bar reflects actual budget usage
- [ ] Top 3 categories display with mini bars
- [ ] Cashflow card shows Income vs Spend
- [ ] Net cashflow calculation is correct
- [ ] Action row has 3 buttons: Expense, Income, Receipt
- [ ] +Expense button opens AddExpenseView
- [ ] +Income button opens IncomeView
- [ ] Insights card shows max 2 insights
- [ ] Pull-to-refresh works

### Activity Screen
- [ ] Transactions grouped by date (Today, Yesterday, Date)
- [ ] Each transaction shows:
  - [ ] Merchant name
  - [ ] Category
  - [ ] Amount with currency (AED, not $)
  - [ ] Time (h:mm a format)
  - [ ] Source badge (SMS/Manual/Receipt/Import)
- [ ] Category icon displays correctly
- [ ] Corrected transactions show orange pencil icon
- [ ] Search filters transactions
- [ ] Category chips filter correctly
- [ ] Date range picker works
- [ ] Tapping transaction opens detail view
- [ ] Correction UI still works in detail view
- [ ] Export to CSV works

### Budgets Screen
- [ ] Overall summary shows total budget vs spent in AED
- [ ] Progress bar shows overall budget usage
- [ ] Individual budgets sorted by % used (highest first)
- [ ] Each budget shows:
  - [ ] Category name with icon
  - [ ] Spent / Budget amount in AED
  - [ ] Remaining or over-budget amount
  - [ ] Progress bar (red if over)
- [ ] "OVER" badge appears when over budget
- [ ] "Manage Budgets" button works
- [ ] Empty state shows when no budgets

### Currency Rules
- [ ] No $ symbols appear for AED amounts
- [ ] Default currency setting in Finance Settings
- [ ] Currency picker shows: AED, USD, EUR, GBP, SAR
- [ ] Transactions display in their original currency
- [ ] AED amounts formatted as "AED 1,234" (no cents for large amounts)

### Dates
- [ ] Every transaction shows time
- [ ] "Unknown time" appears if date is missing/invalid
- [ ] Date groupings are correct (Today, Yesterday, etc.)

### Settings
- [ ] Gear icon opens Finance Settings
- [ ] Settings has 4 tabs: Categories, Recurring, Rules, Settings
- [ ] Currency section shows in Settings tab
- [ ] Default currency can be changed

---

## Exit Criteria

| Criteria | Status |
|----------|--------|
| Finance feels like one screen, not five | ⬜ |
| No $ showing for AED budgets | ⬜ |
| Every transaction shows a date/time | ⬜ |
| Correction UX still works inside transaction detail | ⬜ |

---

## Files Changed

### New Files
- `FinanceActivityView.swift` - Activity tab with improved transaction list
- `FinanceBudgetsView.swift` - Budgets tab
- `AppSettings.swift` - App-wide settings (default currency)

### Modified Files
- `FinanceView.swift` - Complete rewrite with 3-segment control + Overview
- `FinanceComponents.swift` - Fixed $ → formatCurrency, improved TransactionRow
- `FinancePlanningView.swift` - Added Settings tab with currency picker
- `QuickExpenseView.swift` - Fixed $ placeholder text
- `TransactionDetailView.swift` - Already had correction UI (from previous work)
- `FinanceModels.swift` - Already had correction fields (from previous work)

---

## Known Limitations

1. **Receipt scanning**: Button is a stub (no implementation yet)
2. **Currency conversion**: Disabled (amounts show in original currency only)
3. **BNPL**: Moved out of main Finance tab (InstallmentsView still exists)
4. **Insights**: Basic heuristics only (no ML)
5. **MTD Income**: Calculated from positive transaction amounts (may not be accurate if income stored separately)
