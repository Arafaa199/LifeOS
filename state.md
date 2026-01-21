# Claude Coder State

## Current Focus
**FINANCE DATA QUALITY** - Fix categorization, clean merchant names, make finance tab useful.

## Priority TODO (Work on these IN ORDER)

### P0 - CRITICAL (Do First)
- [x] Fix "Other" category transactions (49k AED miscategorized)
  - DONE: Added `Transaction.normalized()` with category inference
- [x] Normalize merchant names
  - DONE: Added merchant mapping for Careem, Carrefour, Lulu, banks, etc.
- [x] Duplicate transaction detection
  - DONE: Added `detectDuplicateTransactions()` to FinanceViewModel

### P1 - HIGH (This Week)
- [x] Add transaction edit capability in FinanceView
  - DONE: Already implemented in TransactionDetailView.swift (EditTransactionView)
- [x] Budget alerts when category exceeds 80%
  - DONE: Already implemented in QuickExpenseView (nearBudgetCategories)
- [x] Add UI to show detected duplicates (use detectDuplicateTransactions())
  - DONE: Added duplicatesSection to InsightsView.swift (commit c633114)
- [ ] Add UI to show normalized merchant names

### P2 - MEDIUM (Next Week)
- [ ] Add spending insights summary card
- [ ] Monthly trend charts
- [ ] Category breakdown pie chart

### P3 - LOW (Backlog)
- [ ] Export transactions to CSV
- [x] Recurring transaction detection (already exists in FinanceViewModel)

## DO NOT TOUCH
- Views that are working (Dashboard, QuickLog, FoodLog)
- DesignSystem.swift (user customized)
- Any file outside Nexus-mobile or Nexus-setup
- User's uncommitted changes

## Active Branches
- nexus-mobile: `main` (all work merged)
- **NO FEATURE BRANCHES** - see new workflow below

## Session History

### 2026-01-21 ~23:00 - Add duplicate detection UI
- **Changed**: Nexus/Views/Finance/InsightsView.swift
- **Reason**: Implemented UI for showing potential duplicate transactions
- **Commit**: c633114
- **Details**:
  - Added `cachedDuplicateGroups` state variable
  - Added `duplicatesSection` and `duplicatesSectionHeader` computed properties
  - Created `DuplicateGroupRow` view component
  - Shows duplicate groups at top of Insights tab with orange warning styling
- **Status**: committed to main

### 2026-01-21 ~14:00 - Human Review & Cleanup
- **Reviewer**: Rafa + Claude (interactive session)
- **Action**: Reviewed 12 accumulated feature branches
- **Problem**: Branches were based on old commits, would delete files if merged
- **Solution**: Cherry-picked useful code, deleted all 12 branches
- **Merged to main**:
  - `detectDuplicateTransactions()` in FinanceViewModel
  - `Transaction.normalized()` with merchant mapping
  - Category inference for "Other" transactions
- **Commit**: d5d4ab9
- **Feedback for Claude Coder**: See "Workflow Problems" below

### 2026-01-21 ~07:30 - State Reset
- **Reason**: Previous branches merged, resetting for new focused work
- **New Focus**: Finance data quality improvements
- **Status**: Ready for next session

### Previous Sessions (Archived)
- 2026-01-21: Fixed async/await in ViewModels (merged)
- 2026-01-21: Consolidated API helpers (merged)
- 2026-01-20: Added generic GET helper (merged)

## Workflow Problems (MUST FIX)

### What Went Wrong
1. **12 branches accumulated** - Owner didn't know to review them
2. **Branches diverged from main** - Rebasing issues caused file deletions
3. **Duplicate work** - Multiple branches did the same thing (generic-post-*)
4. **No notification** - Owner didn't know changes were ready

### New Workflow (MANDATORY)

**BEFORE making changes:**
```bash
cd /Users/rafa/Cyber/Dev/Nexus-mobile
git checkout main
git pull origin main 2>/dev/null || true
```

**AFTER committing:**
1. Do NOT create feature branches
2. Commit directly to main with clear message
3. Owner can `git revert` if needed (easier than branch management)

**OR if branch is required:**
1. Create branch from CURRENT main
2. Make ONE small change
3. Immediately merge back: `git checkout main && git merge branch-name`
4. Delete branch: `git branch -d branch-name`

**Notify owner:**
- Send macOS notification when work is done
- Log what was changed clearly

## Constraints
1. ONE small change per session
2. Must be testable (build should pass)
3. Commit to main directly (easy to revert)
4. Update this file after EVERY session
5. Focus on P1 items now (P0 complete)

## Deleted Files
None

## Notes
- Finance has 280 transactions, 105 in "Other" category
- Main pain point: Can't trust the data because categorization is poor
- User wants app to be useful for daily finance tracking
- P0 items COMPLETE - move to P1 UI improvements
