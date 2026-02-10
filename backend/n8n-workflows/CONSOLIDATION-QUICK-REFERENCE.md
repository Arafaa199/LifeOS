# Daily Summary Workflows - Quick Reference

## The Bottom Line

**Only 2 workflows are needed for the iOS app:**

| Workflow | Status | Purpose |
|----------|--------|---------|
| `daily-summary-api.json` | ACTIVE | Serves `/webhook/nexus-summary` to iOS |
| `daily-summary-update.json` | ACTIVE | Computes summary data daily at 00:05 UTC |

## Three Workflows Should Be Disabled

| Workflow | Why | Action |
|----------|-----|--------|
| `daily-life-summary-api.json` | Not called by iOS app | DISABLE/ARCHIVE |
| `with-auth/daily-summary-api.json` | **Conflicts with root version on same webhook path** | DISABLE immediately |
| `with-auth/lifeos-summaries-api.json` | Experimental, unused endpoints | DISABLE/ARCHIVE |

## What Each Active Workflow Does

### 1. `daily-summary-api.json` (The API)
```
GET /webhook/nexus-summary?date=2024-02-08

Response:
{
  "success": true,
  "data": {
    "date": "2024-02-08",
    "calories": 2100,
    "protein": 85.5,
    "water": 2500,
    "weight": 72.3,
    "mood": 8,
    "energy": 7
  }
}
```

**Called by:** iOS app `DashboardAPI.fetchDailySummary()`
**Database:** `core.daily_summary` table
**Auth:** None

### 2. `daily-summary-update.json` (The Scheduler)
```
Scheduled Trigger: Every day at 00:05 UTC (Dubai time)

SQL Executed:
  - SELECT core.update_daily_summary((yesterday)::date);
  - SELECT core.update_daily_summary((today)::date);

Fetches last 7 days from database for logging
```

**Called by:** n8n scheduler
**Database:** `core.daily_summary` table
**Auth:** None

## Webhook Path Conflict Warning

**CRITICAL:** Both of these listen on the same webhook path:
- `daily-summary-api.json` → `/webhook/nexus-summary`
- `with-auth/daily-summary-api.json` → `/webhook/nexus-summary`

If both are enabled, they will conflict. Only one can be active per webhook path.

Since the iOS app doesn't send authentication, use the root version without auth.

## Recommended Configuration

```yaml
ACTIVE:
  - daily-summary-api.json (root)
  - daily-summary-update.json (root)

DISABLED/ARCHIVED:
  - daily-life-summary-api.json
  - with-auth/daily-summary-api.json
  - with-auth/lifeos-summaries-api.json
```

## Future Authentication

If you need to add authentication later:
- **Option A (Simple):** Enable `with-auth/daily-summary-api.json` instead of root version
  - Requires updating iOS app to send x-api-key header
  - Breaks backward compatibility
  
- **Option B (Recommended):** Modify root version to support optional auth
  - Maintains backward compatibility
  - Simpler client transition path
  
- **Option C (Best Practice):** Add auth at API Gateway level
  - No workflow changes needed
  - Centralized security policy
  - Cleaner separation of concerns

## Files Referenced

For complete analysis, see: `CONSOLIDATION-NOTES.md`

---
Last updated: 2025-02-08
Consolidation Type: Analysis only - no workflows deleted
