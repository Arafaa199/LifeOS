# Dashboard Contracts

## GET /webhook/nexus-dashboard-today

Fetches the complete dashboard payload for today.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |
| Query Params | None |

### Response

```json
{
  "meta": {
    "schema_version": 16,
    "generated_at": "2026-02-08T12:00:00Z",
    "for_date": "2026-02-08",
    "timezone": "Asia/Dubai"
  },
  "today_facts": {
    "day": "2026-02-08",
    "recovery_score": 78,
    "hrv": 45.2,
    "rhr": 52,
    "sleep_minutes": 420,
    "deep_sleep_minutes": 90,
    "rem_sleep_minutes": 110,
    "sleep_efficiency": 0.92,
    "strain": 12.5,
    "steps": 8500,
    "weight_kg": 75.5,
    "spend_total": 150.00,
    "spend_groceries": 45.00,
    "spend_restaurants": 35.00,
    "income_total": 0,
    "transaction_count": 3,
    "meals_logged": 2,
    "water_ml": 2000,
    "calories_consumed": 1800,
    "data_completeness": 0.85
  },
  "trends": [
    { "period": "7d", "avg_recovery": 72, "avg_sleep_minutes": 400 }
  ],
  "feed_status": [
    { "feed": "whoop", "status": "healthy", "lastSync": "2026-02-08T11:00:00Z" }
  ],
  "stale_feeds": [],
  "recent_events": [],
  "daily_insights": {
    "ranked_insights": [
      { "type": "recovery", "confidence": "high", "description": "Recovery above average" }
    ]
  },
  "data_freshness": {
    "health": { "status": "healthy", "last_sync": "2026-02-08T11:00:00Z" },
    "finance": { "status": "healthy", "last_sync": "2026-02-08T10:30:00Z" }
  },
  "fasting": {
    "is_active": false,
    "hours_since_meal": 8.5,
    "last_meal_at": "2026-02-08T12:00:00Z"
  },
  "streaks": {
    "water": { "current": 5, "best": 12 },
    "meals": { "current": 3, "best": 8 },
    "weight": { "current": 10, "best": 15 },
    "workout": { "current": 2, "best": 5 }
  },
  "explain_today": {
    "target_date": "2026-02-08",
    "has_data": true,
    "briefing": "Good recovery day. Spent 150 AED across 3 transactions.",
    "data_gaps": [],
    "data_completeness": 0.85
  },
  "medications_today": {
    "due_today": 5,
    "taken_today": 3,
    "skipped_today": 0,
    "adherence_pct": 60
  },
  "music_today": {
    "tracks_played": 15,
    "total_minutes": 45,
    "unique_artists": 8
  },
  "mood_today": {
    "mood_score": 7,
    "energy_score": 6,
    "logged_at": "2026-02-08T09:00:00Z"
  }
}
```

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

### References

| Type | Reference |
|------|-----------|
| iOS Model | `DashboardPayload.swift` |
| n8n Workflow | `dashboard-today-webhook.json` |
| DB Function | `dashboard.get_payload()` |
| Schema | `_schemas/nexus-dashboard-today.json` |

---

## GET /webhook/nexus-sleep

Fetches sleep data for a specific date.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |
| Query Params | `date` (YYYY-MM-DD, optional, defaults to today) |

### Response

```json
{
  "success": true,
  "date": "2026-02-08",
  "sleep": {
    "sleep_minutes": 420,
    "deep_sleep_minutes": 90,
    "rem_sleep_minutes": 110,
    "light_sleep_minutes": 220,
    "sleep_efficiency": 0.92,
    "sleep_performance": 85,
    "respiratory_rate": 14.5,
    "bedtime": "23:30",
    "wake_time": "06:30"
  }
}
```

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

### References

| Type | Reference |
|------|-----------|
| iOS Model | `DashboardAPI.swift` → `fetchSleep()` |
| n8n Workflow | `sleep-fetch-webhook.json` |
| DB Table | `life.daily_facts`, `health.whoop_sleep` |
| Schema | `_schemas/nexus-sleep.json` |

---

## GET /webhook/nexus-sleep-history

Fetches sleep history for multiple days.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |
| Query Params | `days` (integer, default 7) |

### Response

```json
{
  "success": true,
  "days": [
    {
      "date": "2026-02-08",
      "sleep_minutes": 420,
      "deep_sleep_minutes": 90,
      "rem_sleep_minutes": 110,
      "sleep_efficiency": 0.92,
      "recovery_score": 78
    }
  ]
}
```

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

### References

| Type | Reference |
|------|-----------|
| iOS Model | `DashboardAPI.swift` → `fetchSleepHistory()` |
| n8n Workflow | `sleep-history-webhook.json` |
| DB Table | `life.daily_facts` |
| Schema | `_schemas/nexus-sleep-history.json` |

---

## GET /webhook/nexus-health-timeseries

Fetches health metrics over time.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |
| Query Params | `days` (integer, default 30) |

### Response

```json
{
  "success": true,
  "data": [
    {
      "date": "2026-02-08",
      "recovery_score": 78,
      "hrv": 45.2,
      "rhr": 52,
      "strain": 12.5,
      "sleep_minutes": 420,
      "weight_kg": 75.5,
      "steps": 8500
    }
  ]
}
```

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

### References

| Type | Reference |
|------|-----------|
| iOS Model | `DashboardAPI.swift` → `fetchHealthTimeseries()` |
| n8n Workflow | `health-timeseries-webhook.json` |
| DB Table | `life.daily_facts` |
| Schema | `_schemas/nexus-health-timeseries.json` |

---

## GET /webhook/nexus-sync-status

Fetches sync status across all data domains.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |

### Response

```json
{
  "success": true,
  "domains": [
    {
      "domain": "whoop",
      "last_success_at": "2026-02-08T12:00:00Z",
      "last_success_rows": 5,
      "last_success_duration_ms": 1200,
      "last_success_source": "n8n",
      "freshness": "healthy",
      "seconds_since_success": 300
    }
  ],
  "timestamp": "2026-02-08T12:05:00Z"
}
```

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

### References

| Type | Reference |
|------|-----------|
| iOS Model | `NexusModels.swift` → `SyncStatusResponse` |
| n8n Workflow | `sync-status-webhook.json` |
| DB Table | `ops.sync_runs` |

---

## POST /webhook/nexus-whoop-refresh

Triggers a WHOOP data sync.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |
| Body | None or `{}` |

### Response

```json
{
  "success": true,
  "message": "WHOOP refresh triggered"
}
```

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

### References

| Type | Reference |
|------|-----------|
| iOS Model | `DashboardAPI.swift` → `triggerWhoopRefresh()` |
| n8n Workflow | `whoop-refresh-webhook.json` |
| DB Table | `health.whoop_*` |

