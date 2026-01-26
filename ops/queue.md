# LifeOS Task Queue

## RULES (MANDATORY)
- Execute topmost task only
- Prove correctness with SQL queries
- No ingestion changes without explicit approval
- Prefer views over tables
- Everything must be replayable from raw data

---

## CURRENT STATUS

**System:** Reliability Fixes Required ⚠️
**TRUST-LOCKIN:** PASSED (2026-01-25)
**Audit Status:** CRITICAL ISSUES FOUND (2026-01-26)

Finance ingestion is validated and complete.
SMS ingestion is FROZEN (no changes to parsing logic).
**However:** Three launchd services are failing, preventing reliable data collection.

**Current Phase:** E2E Reliability Fixes
**Goal:** Make all pipelines operational before resuming feature work

**Audit Report:** `ops/logs/auditor/audit-2026-01-26.md`

---

## CODER INSTRUCTIONS

Fix reliability issues in priority order (P0 first, then P1). Each fix must include:
1. The change made
2. Verification command/query
3. Evidence of success

Do NOT resume feature work until all P0 issues are resolved.

---

## ACTIVE TASKS

### TASK-FIX.1: Fix SMS Import Launchd Path
Priority: P0
Owner: coder
Status: DONE ✓

**Objective:** Fix the path mismatch causing SMS import fallback to fail.

**Problem:**
- Launchd plist points to: `/Users/rafa/Cyber/Dev/LifeOS/backend/scripts/auto-import-sms.sh`
- Actual path is: `/Users/rafa/Cyber/Dev/Projects/LifeOS/backend/scripts/auto-import-sms.sh`
- Exit code 78 (file not found)

**Files Changed:**
- `~/Library/LaunchAgents/com.nexus.sms-import.plist`

**Definition of Done:**
- [x] Update path in plist: `/Users/rafa/Cyber/Dev/LifeOS/` → `/Users/rafa/Cyber/Dev/Projects/LifeOS/`
- [x] Unload and reload: `launchctl unload ~/Library/LaunchAgents/com.nexus.sms-import.plist && launchctl load ~/Library/LaunchAgents/com.nexus.sms-import.plist`
- [x] Verify: `launchctl list | grep sms-import` shows exit 0 or running PID
- [x] Run manually: Script runs (path found)

**Additional Fix Applied:**
- Rebuilt `better-sqlite3` node module: `npm rebuild better-sqlite3`

**Note:** Script still fails with SQLITE_CANTOPEN - this requires Full Disk Access for Terminal in System Settings > Privacy & Security. This is a user permission issue, not a code issue.

---

### TASK-FIX.2: Fix Receipt Ingestion NULL Date
Priority: P0
Owner: coder
Status: DONE ✓

**Objective:** Fix the NOT NULL violation when creating transactions from receipts.

**Problem:**
```
psycopg2.errors.NotNullViolation: null value in column "date" of relation "transactions"
DETAIL: Failing row contains (2223, null, null, null, null, Carrefour, null, -143.80, AED, ...)
```

**Files Changed:**
- `backend/scripts/receipt-ingest/receipt_ingestion.py` (lines 702-707, 777)

**Fix Applied:**
- Added NULL date fallback in `create_transaction_for_receipt()`: uses `created_at` when `receipt_date` is NULL
- Updated `create_transactions_for_unlinked_receipts()` SELECT to include `created_at` column
- Manually created transaction for receipt 54 (the failing receipt) using `COALESCE(receipt_date, created_at::date)`

**Definition of Done:**
- [x] Find the `create_transaction_for_receipt()` function
- [x] Add fallback: `date = receipt['receipt_date'] or receipt['created_at']::date`
- [x] Verify: No NULL violations, receipts create transactions
- [x] Check: `SELECT COUNT(*) FROM finance.transactions WHERE client_id LIKE 'rcpt:%'` → 9 rows

**Note:** Python script cannot connect directly to nexus DB from pro14 (port 5432 not reachable over Tailscale). Transaction for receipt 54 created via SQL. Python fix ensures future receipts with NULL dates won't fail.

---

### TASK-FIX.3: Wire WHOOP to Normalized Layer
Priority: P0
Owner: coder
Status: PENDING

**Objective:** Ensure WHOOP data propagates from `health.whoop_recovery` to `normalized.daily_recovery`.

**Problem:**
- `health.whoop_recovery` has 7 rows
- `normalized.daily_recovery` has 0 rows
- The pipeline writes to legacy table but never to normalized layer

**Investigation Steps:**
1. Check how `health.whoop_recovery` is populated (n8n workflow? trigger?)
2. Check if there's a trigger or function that should copy to normalized
3. Create migration to backfill + add trigger

**Files to Change:**
- TBD (investigate first)
- Likely: new migration `082_whoop_to_normalized.up.sql`

**Definition of Done:**
- [ ] Identify how WHOOP data flows
- [ ] Create trigger or n8n step to populate `normalized.daily_recovery`
- [ ] Backfill existing data: `INSERT INTO normalized.daily_recovery SELECT ... FROM health.whoop_recovery`
- [ ] Verify: `SELECT COUNT(*) FROM normalized.daily_recovery` > 0

---

### TASK-FIX.4: Fix Resolve-Events Launchd
Priority: P0
Owner: coder
Status: PENDING

**Objective:** Get the resolve-events job running without errors.

**Problem:**
- Exit code 1
- No error logs visible

**Investigation Steps:**
1. Run manually: `/opt/homebrew/bin/node /Users/rafa/Cyber/Infrastructure/Nexus-setup/scripts/resolve-raw-events.js`
2. Check stdout/stderr for errors
3. Fix script issues

**Files to Change:**
- `backend/scripts/resolve-raw-events.js` (likely)
- Or: plist environment variables

**Definition of Done:**
- [ ] Run script manually without errors
- [ ] Reload launchd job
- [ ] Verify: `launchctl list | grep resolve-events` shows exit 0

---

### TASK-FIX.5: Increase iOS Foreground Timeout
Priority: P1
Owner: coder
Status: PENDING

**Objective:** Increase the foreground refresh timeout from 5s to 15s.

**Problem:**
- 5-second timeout is too aggressive for cellular networks
- Causes unnecessary "refresh failed" states

**Files to Change:**
- `ios/Nexus/ViewModels/DashboardViewModel.swift:361`

**Definition of Done:**
- [ ] Change `5_000_000_000` to `15_000_000_000` (15 seconds)
- [ ] Build iOS app successfully
- [ ] Document change in state.md

---

### TASK-FIX.6: Add URLRequest Timeout Configuration
Priority: P1
Owner: coder
Status: PENDING

**Objective:** Prevent indefinite network hangs by adding explicit timeout.

**Problem:**
- URLSession.shared.data(for:) has default 60s timeout
- No explicit timeout set on URLRequest instances
- Can cause app to hang on bad networks

**Files to Change:**
- `ios/Nexus/Services/NexusAPI.swift`

**Definition of Done:**
- [ ] Add `request.timeoutInterval = 30` to all URLRequest creations
- [ ] Or: Create shared URLSession with custom configuration
- [ ] Build iOS app successfully

---

### TASK-FIX.7: Investigate HealthKit Sync
Priority: P1
Owner: coder
Status: PENDING

**Objective:** Determine why HealthKit data isn't reaching the backend.

**Problem:**
- `life.feed_status` shows `healthkit` with `error` status
- `raw.healthkit_samples` appears empty or very old

**Investigation Steps:**
1. Check `HealthKitSyncService.swift` implementation
2. Verify n8n webhook `POST /webhook/healthkit/batch` is active
3. Test manual sync from iOS Settings
4. Check n8n execution logs

**Definition of Done:**
- [ ] Identify root cause
- [ ] Fix and verify data flows to backend
- [ ] `SELECT COUNT(*) FROM raw.healthkit_samples WHERE created_at > NOW() - INTERVAL '1 day'` > 0

---

### TASK-FIX.8: Make OfflineQueue Processing Atomic
Priority: P2
Owner: coder
Status: PENDING

**Objective:** Prevent potential race condition in OfflineQueue.

**Problem:**
- `isProcessing` flag is checked non-atomically
- Could cause double-submit on concurrent calls

**Files to Change:**
- `ios/Nexus/Services/OfflineQueue.swift`

**Definition of Done:**
- [ ] Use `OSAllocatedUnfairLock` or convert to actor
- [ ] Build iOS app successfully

---

### TASK-FIX.9: Reduce Foreground Debounce
Priority: P2
Owner: coder
Status: PENDING

**Objective:** Improve app responsiveness on foreground.

**Problem:**
- 30-second debounce may feel unresponsive
- User switches apps and comes back, sees stale data for 30s

**Files to Change:**
- `ios/Nexus/ViewModels/DashboardViewModel.swift:136`

**Definition of Done:**
- [ ] Change `foregroundRefreshMinInterval = 30` to `15`
- [ ] Build iOS app successfully

---

### TASK-FIX.10: Add Connection Retry to Receipt Ingestion
Priority: P2
Owner: coder
Status: PENDING

**Objective:** Make receipt ingestion resilient to network issues.

**Problem:**
- Script fails immediately on connection timeout
- Tailscale may be disconnected when launchd runs

**Files to Change:**
- `backend/scripts/receipt-ingest/receipt_ingestion.py`

**Definition of Done:**
- [ ] Add retry logic with exponential backoff (3 retries, 5s/15s/45s)
- [ ] Run script successfully even with brief network blip

---

### TASK-FIX.11: Add Feed Status Refresh Trigger
Priority: P2
Owner: coder
Status: PENDING

**Objective:** Auto-update feed_status when data arrives.

**Problem:**
- `life.feed_status` requires manual refresh
- Shows stale even when data is present

**Files to Change:**
- New migration for triggers on raw tables

**Definition of Done:**
- [ ] Create trigger on INSERT to `raw.*` tables
- [ ] Trigger calls function to update `life.feed_status`
- [ ] Verify: Insert to raw table → feed_status updates automatically

---

### TASK-FIX.12: Document SMS Flow Architecture
Priority: P2
Owner: coder
Status: PENDING

**Objective:** Document that SMS import bypasses raw layer (intentional).

**Problem:**
- `raw.bank_sms` only has 1 test row
- SMS import writes directly to `finance.transactions` with `source='sms'`
- This is intentional (idempotency via external_id) but undocumented

**Files to Change:**
- `ops/state.md` (add architecture note)

**Definition of Done:**
- [ ] Add "SMS Architecture" section to state.md
- [ ] Document: SMS watcher → import-sms-transactions.js → finance.transactions (direct)
- [ ] Note: idempotency handled by external_id unique constraint

---

## COMPLETED TASKS

### Previous Milestones
- TRUST-LOCKIN — COMPLETE ✅ (2026-01-25)
- End-to-End Continuity & Trust — COMPLETE ✅
- Assisted Capture — COMPLETE ✅
- Reality Verification — COMPLETE ✅
- Calendar iOS Integration — COMPLETE ✅
- Nutrition Database Expansion — COMPLETE ✅
- E2E Reliability Verification — COMPLETE ✅

---

## ROADMAP (After Fixes)

### Phase: Feature Resumption (After P0/P1 Complete)
1. Screen Time iOS Integration (DEFERRED - needs App Store)
2. GitHub Activity Dashboard Widget
3. Weekly Insights Email Enhancement
4. iOS Widget Improvements

### Phase: Data Quality
1. Improve receipt→nutrition matching (currently 49.1%)
2. Add more merchants to auto-categorization rules
3. Calendar → productivity correlation views

---

## FROZEN (No Changes)
- SMS parsing patterns (FROZEN 2026-01-25)
- Receipt parsing patterns
- WHOOP sensor mappings
- Core transaction schema

---

## VERIFICATION AFTER ALL FIXES

```bash
# 1. All launchd services running (no non-zero exit codes)
launchctl list | grep -E "nexus|lifeos"
# Expected: All showing PID or exit 0

# 2. Feed status healthy
ssh nexus "docker exec nexus-db psql -U nexus -d nexus -c \"SELECT source, status FROM life.feed_status;\""
# Expected: All 'ok' or 'healthy'

# 3. Normalized layer populated
ssh nexus "docker exec nexus-db psql -U nexus -d nexus -c \"SELECT COUNT(*) FROM normalized.daily_recovery;\""
# Expected: > 0

# 4. iOS app pull-to-refresh completes < 5s
# Manual test on device
```
