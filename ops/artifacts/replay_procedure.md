# LifeOS Replay Procedure

**Purpose:** Verify data pipeline determinism and rebuild derived tables from source data.

**Created:** 2026-01-25
**Owner:** Coder (TASK-VERIFY.2)

---

## Overview

The replay procedure proves that LifeOS data pipeline is **deterministic** - meaning the same source data always produces identical derived outputs. This is critical for:

1. **Data Trust**: Ensures calculations are repeatable and verifiable
2. **Debugging**: Allows rolling back to raw data and rebuilding
3. **Migration Safety**: Validates schema changes preserve data integrity
4. **Audit Compliance**: Provides evidence trail for all transformations

---

## Scripts

### Primary Script

**Location:** `backend/scripts/replay-last-30-days.sh`

**What it does:**
1. Takes pre-replay snapshot of all table counts
2. Creates full database backup to `/tmp/lifeos-replay-backup-YYYYMMDD-HHMMSS/`
3. Truncates derived tables (last 30 days only)
4. Refreshes materialized views
5. Rebuilds facts via `life.refresh_all(30)`
6. Regenerates insights for each day
7. Takes post-replay snapshot
8. Compares counts and validates determinism

**Exit codes:**
- `0` = PASS (all counts match)
- `1` = FAIL (source tables changed or critical discrepancies)

---

## Data Architecture

### Source Tables (NEVER TRUNCATED)
These tables contain immutable source data:

```
raw.bank_sms              -- SMS messages from chat.db
raw.healthkit_samples     -- HealthKit data from iOS
raw.github_events         -- GitHub activity
finance.budgets           -- Budget definitions
finance.categories        -- Category definitions
finance.merchant_rules    -- Auto-categorization rules
```

**Critical:** If these tables change during replay, the test FAILS.

### Derived Tables (REBUILT DURING REPLAY)
These tables are computed from source data:

```
finance.transactions      -- Parsed transactions (from raw.bank_sms)
finance.receipts          -- Receipt records
finance.receipt_items     -- Line items from receipts
life.daily_facts          -- Daily aggregated metrics
facts.daily_health        -- Health facts by day
facts.daily_finance       -- Finance facts by day
facts.daily_nutrition     -- Nutrition facts by day
insights.daily_anomalies  -- Detected anomalies
insights.weekly_reports   -- Weekly summaries
```

**Note:** Replay only rebuilds **last 30 days** of derived data (not full history).

---

## Usage

### Basic Run

```bash
cd ~/Cyber/Dev/Projects/LifeOS/backend/scripts
./replay-last-30-days.sh
```

**Expected output:**
```
═══════════════════════════════════════════════════════════════
LifeOS - Deterministic Replay (Last 30 Days)
═══════════════════════════════════════════════════════════════

PHASE 1: Creating pre-replay snapshot...
PHASE 2: Creating database backup...
✓ Backup created: /tmp/lifeos-replay-backup-20260125-220000/nexus-full-backup.sql (2.3M)
PHASE 3: Truncating derived tables (last 30 days)...
✓ Derived tables truncated (last 30 days)
PHASE 4: Refreshing materialized views...
✓ Materialized views refreshed
PHASE 5: Rebuilding facts for last 30 days...
✓ Facts rebuilt
PHASE 6: Regenerating insights...
✓ Insights regenerated
PHASE 7: Creating post-replay snapshot...
PHASE 8: VERIFICATION
✓ PASS: All counts match perfectly (deterministic)

═══════════════════════════════════════════════════════════════
REPLAY COMPLETE - PASS
═══════════════════════════════════════════════════════════════

Backup location: /tmp/lifeos-replay-backup-20260125-220000
```

### Restore from Backup (if needed)

```bash
BACKUP_DIR=/tmp/lifeos-replay-backup-20260125-220000
ssh nexus "docker exec -i nexus-db psql -U nexus -d nexus" < $BACKUP_DIR/nexus-full-backup.sql
```

---

## Verification Criteria

### PASS Criteria

1. **Source table counts unchanged**
   - `raw.bank_sms` count identical
   - `finance.budgets` count identical
   - All other source tables stable

2. **Derived table counts match ±0**
   - `life.daily_facts` (last 30 days) count identical
   - `finance.transactions` count identical
   - All fact/insight tables match exactly

3. **Total amounts unchanged**
   - Sum of `finance.transactions.amount` (last 30d) identical
   - Sum of `life.daily_facts.recovery_score` (last 30d) identical

4. **No duplicate keys**
   - `COUNT(*) = COUNT(DISTINCT external_id)` for transactions
   - `COUNT(*) = COUNT(DISTINCT day)` for daily_facts

### FAIL Criteria

1. **Source tables modified** (data loss risk)
2. **Derived totals differ by >0.01** (calculation drift)
3. **Duplicate keys detected** (idempotency broken)

### WARNING Criteria

1. **Minor count differences** (investigate but not critical)
2. **Missing optional data** (e.g., insights not regenerated)

---

## Troubleshooting

### "Source tables changed" error

**Cause:** Raw data was modified during replay (should never happen)

**Fix:**
1. Restore from backup immediately
2. Investigate what modified raw tables
3. Fix the root cause before retrying

### "Derived counts differ" warning

**Cause:** Rebuild logic may have changed or data race condition

**Fix:**
1. Check `pre_counts.txt` vs `post_counts.txt` in backup dir
2. Identify which table(s) differ
3. Re-run replay script to confirm (may be timing issue)
4. If persists, investigate rebuild functions

### "Materialized view refresh failed"

**Cause:** View may not exist (expected for new installations)

**Fix:** Ignore warnings for non-existent views (they're optional optimizations)

---

## Frequency

**Recommended schedule:**

- **Before major migrations:** Always run replay to validate no data loss
- **Weekly:** Run as part of system health check
- **After schema changes:** Verify determinism preserved
- **On-demand:** When investigating data discrepancies

**Automated:** Consider adding to weekly cron job after stabilization

---

## Performance

**Typical runtime:** 30-60 seconds (depends on data volume)

**Bottlenecks:**
- Database backup (2-5s)
- Materialized view refresh (5-10s)
- Insight regeneration (30 iterations × 0.5s = 15s)

**Optimization notes:**
- Script uses CONCURRENTLY for materialized views (non-blocking)
- Only rebuilds last 30 days (not full history)
- Parallel insight generation possible (future improvement)

---

## Safety Notes

1. **Non-destructive:** Creates full backup before any changes
2. **Limited scope:** Only affects last 30 days of derived data
3. **Read-only sources:** Never modifies raw.* or finance.budgets/categories
4. **Idempotent:** Safe to run multiple times
5. **Rollback ready:** Backup provided with every run

---

## Example Output Files

### pre_counts.txt
```
=== PRE-REPLAY COUNTS (Sat Jan 25 22:00:00 GST 2026) ===

SOURCE TABLES (should remain unchanged):
raw.bank_sms: 343
finance.budgets: 21
finance.categories: 16

DERIVED TABLES (will be rebuilt):
finance.transactions: 147
life.daily_facts: 30

TOTALS (for validation):
Total spend (last 30d): -15234.50
Total recovery score (last 30d): 1620
```

### post_counts.txt
```
=== POST-REPLAY COUNTS (Sat Jan 25 22:01:00 GST 2026) ===

SOURCE TABLES (should remain unchanged):
raw.bank_sms: 343
finance.budgets: 21
finance.categories: 16

DERIVED TABLES (rebuilt):
finance.transactions: 147
life.daily_facts: 30

TOTALS (for validation):
Total spend (last 30d): -15234.50
Total recovery score (last 30d): 1620
```

**Verdict:** PASS (all counts match)

---

## Related Documentation

- **Migration Guide:** `ops/artifacts/sql/` (database schema migrations)
- **Data Pipeline:** See `life.refresh_all()` function in migration 040
- **Insight Generation:** See `insights.generate_daily_summary()` in migration 042
- **Full Replay:** See `scripts/replay-full.sh` for complete rebuild (all history)

---

**Last Updated:** 2026-01-25
**Status:** Active
**Owned By:** Coder
