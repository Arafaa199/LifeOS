# Deprecated Views/Functions After Migration 071

## Migration 071: Canonical Daily Summary
**Created:** 2026-01-25T22:40+04
**Purpose:** Single source of truth for daily summary data

## NEW Canonical Resources

### Materialized View
- `life.mv_daily_summary` — Canonical daily summary materialized view
  - Single source combining health, finance, nutrition, behavioral metrics
  - Updated via `life.refresh_daily_summary(date)`
  - Fast lookups via unique index on `day`

### Functions
- `life.refresh_daily_summary(DATE)` — Refresh canonical view for specific date
- `life.get_daily_summary_canonical(DATE)` — Get daily summary as JSONB

## KEPT (Still in Use)

### Functions
- `life.get_daily_summary(DATE)` — KEPT: Used by existing n8n workflows and iOS app
  - Migration path: Eventually replace with `get_daily_summary_canonical()`
  - Status: Active, do not delete yet
- `life.refresh_daily_facts(DATE)` — KEPT: Underlying data refresh (called by refresh_daily_summary)
- `life.get_environment_summary(DATE)` — KEPT: Specialized environment metrics

### Tables
- `life.daily_facts` — KEPT: Source table for materialized view
  - This is the underlying data store, not deprecated

## USAGE GUIDANCE

### For Dashboard Queries
**Recommended:** Use `life.mv_daily_summary` directly
```sql
SELECT * FROM life.mv_daily_summary WHERE day = '2026-01-24';
```

**For API responses:** Use `life.get_daily_summary_canonical(DATE)`
```sql
SELECT life.get_daily_summary_canonical('2026-01-24');
```

### For Data Refresh
**Always use:** `life.refresh_daily_summary(DATE)`
```sql
SELECT life.refresh_daily_summary(CURRENT_DATE);
```
This will:
1. Call `life.refresh_daily_facts(DATE)` to update source data
2. Refresh the materialized view

## MIGRATION PATH

1. **Phase 1 (Current):** Both old and new functions coexist
   - `life.get_daily_summary()` still works (uses daily_facts)
   - `life.get_daily_summary_canonical()` available (uses mv_daily_summary)

2. **Phase 2 (Future - TASK-VERIFY.4):** Update iOS app and n8n workflows
   - Change API calls from `get_daily_summary()` to `get_daily_summary_canonical()`
   - Verify parity between outputs

3. **Phase 3 (Future):** Deprecate old function
   - Mark `life.get_daily_summary()` as deprecated
   - Eventually remove after all clients migrated

## PERFORMANCE COMPARISON

| Method | Query Time | Notes |
|--------|------------|-------|
| `mv_daily_summary` direct | ~0.03ms | Fastest (materialized) |
| `get_daily_summary_canonical()` | ~0.5ms | Single query on materialized view |
| `get_daily_summary()` (old) | ~8-20ms | Multiple joins on source tables |

## VERIFIED

- [x] Materialized view created with 92 rows
- [x] Data matches `life.daily_facts` exactly
- [x] Unique index on `day` for fast lookups
- [x] Refresh function works correctly
- [x] JSONB function returns proper structure
- [x] Performance < 1ms for single-day queries
