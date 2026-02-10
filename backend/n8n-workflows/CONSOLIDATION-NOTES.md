# Daily Summary Workflows - Consolidation Analysis

## Executive Summary

There are **4 daily-summary workflows** in the n8n-workflows directory with significant overlap:
- 2 in the root directory (`daily-summary-api.json`, `daily-summary-update.json`, `daily-life-summary-api.json`)
- 2 in the `with-auth/` directory (`daily-summary-api.json`, `lifeos-summaries-api.json`)

**Active usage in iOS app:** Only `/webhook/nexus-summary` is actively called by the iOS codebase (from `DashboardAPI.swift`).

---

## Detailed Workflow Comparison

### 1. Root Directory Workflows

#### `daily-summary-api.json` (NO AUTH VERSION)
- **Webhook Path:** `/webhook/nexus-summary`
- **Webhook ID:** `nexus-summary-api-v4`
- **HTTP Method:** GET
- **Query Params:** Optional `date` parameter
- **SQL Query:**
  ```sql
  SELECT
    COALESCE(ds.date::text, '{{ $json.targetDate }}') as date,
    COALESCE(ds.calories_consumed, 0) as calories,
    COALESCE(ds.protein_g, 0) as protein,
    COALESCE(ds.water_ml, 0) as water,
    COALESCE(ds.weight_kg, cm.value) as weight,
    ds.recovery_score as mood,
    ds.steps as energy
  FROM (SELECT 1) dummy
  LEFT JOIN core.daily_summary ds ON ds.date = '{{ $json.targetDate }}'::date
  LEFT JOIN core.current_metrics cm ON cm.key = 'weight'
  ```
- **Response Format:**
  ```json
  {
    "success": true,
    "data": {
      "date": "YYYY-MM-DD",
      "calories": 0,
      "protein": 0.0,
      "water": 0,
      "weight": null,
      "mood": null,
      "energy": null,
      "logs": []
    }
  }
  ```
- **Auth:** None
- **Usage:** **ACTIVELY USED** by iOS app (`DashboardAPI.fetchDailySummary()`)
- **Status:** **CANONICAL** - Keep this one
- **Node Count:** 5 (webhook → parse-date → get-summary → format → respond)

---

#### `daily-summary-update.json`
- **Trigger:** Scheduled (every day at 00:05 UTC in Dubai timezone)
- **HTTP Method:** Not applicable (scheduled trigger)
- **Primary SQL Query:**
  ```sql
  SELECT core.update_daily_summary((NOW() AT TIME ZONE 'Asia/Dubai')::date - INTERVAL '1 day');
  SELECT core.update_daily_summary((NOW() AT TIME ZONE 'Asia/Dubai')::date);
  ```
- **Secondary Query:** Retrieves last 7 days of summaries from `core.daily_summary`
- **Output:** Markdown formatted summary of last 7 days
- **Auth:** None
- **Purpose:** Daily background job to compute/update the daily summary table
- **Status:** **COMPLEMENTARY** - Keeps summary data fresh for the API
- **Node Count:** 6 (schedule-trigger → update-summary → get-recent → check-results → format-output/no-op)

---

#### `daily-life-summary-api.json`
- **Webhook Path:** `/webhook/nexus-daily-summary`
- **Webhook ID:** `nexus-daily-summary-v2`
- **HTTP Method:** GET
- **Query Params:** None
- **SQL Query:**
  ```sql
  SELECT life.get_daily_summary((NOW() AT TIME ZONE 'Asia/Dubai')::date) AS payload;
  ```
- **Response Format:** Raw JSON payload from `life.get_daily_summary()` function (structure unknown without DB inspection)
- **Auth:** None
- **Usage:** **NOT ACTIVELY USED** - No references found in iOS codebase
- **Status:** **REDUNDANT/DEPRECATED** - Different endpoint path and uses different DB schema
- **Active Field:** `true` (marked as active in JSON)
- **Node Count:** 3 (webhook → get-payload → respond)

---

### 2. With-Auth Directory Workflows

#### `with-auth/daily-summary-api.json` (WITH AUTH VERSION)
- **Webhook Path:** `/webhook/nexus-summary` (SAME as root version)
- **Webhook ID:** `nexus-summary-api-v4` (SAME as root version)
- **HTTP Method:** GET
- **Auth Mechanism:** API Key validation via `x-api-key` header against `$env.NEXUS_API_KEY`
- **Query Params:** Optional `date` parameter
- **SQL Query:** Identical to the root version
- **Response Format:** Identical to the root version + 401 Unauthorized response for invalid keys
- **Usage:** **NOT ACTIVELY USED** - iOS app doesn't send API keys
- **Status:** **SUPERSEDED** - This is an authenticated version of the root `daily-summary-api.json`
- **Issue:** Duplicate webhook path creates conflict if both are active simultaneously
- **Node Count:** 7 (webhook → check-api-key → parse-date → get-summary → format → respond/unauthorized)

---

#### `with-auth/lifeos-summaries-api.json`
- **Webhook Paths:** 3 endpoints in one workflow:
  1. `/webhook/nexus-daily-summary` (GET) - Fetches from `insights.daily_finance_summary`
  2. `/webhook/nexus-weekly-report` (GET) - Fetches from `insights.weekly_reports`
  3. `/webhook/nexus-system-health` (GET) - Fetches from `ops.v_pipeline_health`, `ops.v_dashboard_health_summary`, `ops.v_active_alerts`, `finance.v_budget_summary`
- **Auth:** None implemented in this workflow
- **Usage:** **NOT ACTIVELY USED** - No references found in iOS codebase
- **Status:** **EXPERIMENTAL/UNUSED** - Provides additional endpoints but not consumed
- **Note:** Despite being in `with-auth/`, it has no authentication implemented
- **Node Count:** 9 (3 webhooks → 3 fetch nodes → 3 respond nodes)

---

## Key Findings

### Overlaps & Conflicts

1. **Same Webhook Path Conflict**
   - Both `daily-summary-api.json` (root) and `with-auth/daily-summary-api.json` use `/webhook/nexus-summary`
   - This will cause routing conflicts if both are enabled in n8n simultaneously

2. **Unused Endpoints**
   - `daily-life-summary-api.json` - mapped to `/webhook/nexus-daily-summary` but not called by iOS
   - `lifeos-summaries-api.json` - three endpoints defined but none are called by iOS

3. **Redundant Scheduled Updates**
   - Only `daily-summary-update.json` performs the actual summary computation
   - This is necessary and should be kept

---

## Recommendations

### Immediate Actions

1. **Keep as CANONICAL:**
   - ✅ `daily-summary-api.json` (root) - This is the only one iOS uses

2. **Keep as SUPPORTING:**
   - ✅ `daily-summary-update.json` - Performs the daily computation that feeds the API

3. **Mark as DEPRECATED:**
   - ❌ `with-auth/daily-summary-api.json` - Duplicate endpoint, unused
   - ❌ `daily-life-summary-api.json` - Unused by iOS
   - ❌ `with-auth/lifeos-summaries-api.json` - Experimental endpoints, unused

### Long-term Strategy

**If authentication is needed in the future:**
- Do NOT create `/with-auth/` versions with duplicate paths
- Instead, modify the canonical `daily-summary-api.json` to support auth as an optional feature
- Or create authentication at the reverse proxy/API gateway level

**For unused endpoints:**
- Determine if `lifeos-summaries-api.json` serves any internal reporting needs
- If not needed, can be safely deleted after backing up
- `daily-life-summary-api.json` appears to be an experimental prototype that was superseded

### File Modifications Needed

None required at this time. The conflicts will only manifest if:
1. Both `daily-summary-api.json` AND `with-auth/daily-summary-api.json` are **active** in n8n
2. Both are listening on the same webhook ID

**Current workaround:** Keep only root `daily-summary-api.json` enabled and disable the `with-auth/` version.

---

## Implementation Notes

### Database Dependencies

All workflows depend on:
- **Primary:** `core.daily_summary` table
- **Update function:** `core.update_daily_summary(date)`
- **Metrics:** `core.current_metrics` table for weight lookup
- **Schema:** `life.get_daily_summary()` function (if used)
- **Financial:** `insights.daily_finance_summary` table (for `lifeos-summaries-api`)

### Environment Variables

- `NEXUS_API_KEY` - Used in the `with-auth/` versions for API key validation
- Timezone: All queries use `Asia/Dubai` as the reference timezone

---

## Appendix: Migration Path (If Authentication is Needed Later)

If the iOS app needs to authenticate API requests:

**Option A: Enable the with-auth version**
```
1. Disable root/daily-summary-api.json
2. Enable with-auth/daily-summary-api.json
3. Update iOS app to send x-api-key header
4. Risk: Breaks all current unauthenticated calls
```

**Option B: Add auth to canonical version (Recommended)**
```
1. Modify daily-summary-api.json to include optional API key check
2. Maintain backward compatibility for unauthenticated calls
3. Enable authentication for specific API consumers
4. Lower risk migration path
```

**Option C: API Gateway Authentication (Best Practice)**
```
1. Remove auth from individual workflows
2. Implement authentication at reverse proxy level
3. Simpler workflow management
4. Centralized security policy
```

---

## Conclusion

The iOS app is designed to call only `/webhook/nexus-summary` via the root `daily-summary-api.json` workflow. The with-auth versions and alternative endpoints are either experimental, redundant, or superseded.

**Recommendation: Consolidate by keeping root directory workflows active and documenting the with-auth versions as deprecated.**
