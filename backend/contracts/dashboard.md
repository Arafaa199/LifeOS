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
  "schema_version": 21,
  "generated_at": "2026-02-09T12:00:00Z",
  "target_date": "2026-02-09",
  "today_facts": {
    "day": "2026-02-09",
    "recovery_score": 78,
    "hrv": 45.2,
    "rhr": 52,
    "sleep_minutes": 420,
    "sleep_hours": 7.0,
    "deep_sleep_minutes": 90,
    "rem_sleep_minutes": 110,
    "deep_sleep_hours": 1.5,
    "sleep_efficiency": 0.92,
    "strain": 12.5,
    "weight_kg": 75.5,
    "spend_total": 150.00,
    "spend_groceries": 45.00,
    "spend_restaurants": 35.00,
    "income_total": 0,
    "transaction_count": 3,
    "spend_vs_7d": -12.5,
    "spend_unusual": false,
    "meals_logged": 2,
    "water_ml": 2000,
    "calories_consumed": 1800,
    "protein_g": 120.5,
    "data_completeness": 0.85,
    "avg_mood": 7,
    "avg_energy": 6
  },
  "finance_summary": {
    "spend_total": 150.00,
    "spend_groceries": 45.00,
    "spend_restaurants": 35.00,
    "spend_transport": 0,
    "income_total": 0,
    "transaction_count": 3
  },
  "feed_status": [
    { "feed": "whoop", "status": "healthy", "lastSync": "2026-02-09T11:00:00Z", "hoursSinceSync": 1.5 }
  ],
  "stale_feeds": [],
  "daily_insights": {
    "ranked_insights": [
      { "type": "recovery", "confidence": "high", "description": "Recovery above average" }
    ]
  },
  "calendar_summary": {
    "meeting_count": 0,
    "meeting_hours": 0,
    "first_meeting": null,
    "last_meeting": null
  },
  "reminder_summary": {
    "due_today": 3,
    "completed_today": 1,
    "overdue_count": 2
  },
  "github_activity": {},
  "fasting": {
    "is_active": false,
    "hours_since_meal": 8.5,
    "last_meal_at": "2026-02-09T12:00:00Z"
  },
  "medications_today": {
    "due_today": 5,
    "taken_today": 3,
    "skipped_today": 0,
    "adherence_pct": 60,
    "medications": [
      { "name": "Vitamin D", "status": "taken", "scheduled_time": "08:00:00", "taken_at": "2026-02-09T08:15:00Z" }
    ]
  },
  "explain_today": {
    "target_date": "2026-02-09",
    "has_data": true,
    "health": {
      "recovery_label": "high",
      "sleep_label": "good",
      "recovery_score": 78,
      "sleep_hours": 7.0,
      "hrv": 45.2,
      "strain": 12.5,
      "weight_kg": 75.5,
      "summary": ["Recovery: 78% (high)", "Sleep: 7.0h (good)", "Deep sleep: 90 min"]
    },
    "finance": {
      "spend_label": "normal",
      "spend_total": 150.00,
      "transaction_count": 3,
      "summary": ["Spend: 150 AED (normal)"]
    },
    "nutrition": {
      "meals_logged": 2,
      "calories": 1800,
      "protein_g": 120.5,
      "water_ml": 2000,
      "summary": ["2 meal(s)", "1800 kcal", "120.5g protein", "2.0L water"]
    },
    "activity": {
      "listening_minutes": 45,
      "fasting_hours": 14.2,
      "reminders_due": 3,
      "reminders_completed": 1,
      "work_minutes": 480,
      "summary": ["8.0h at work", "45m music", "14.2h fasted"]
    },
    "briefing": "Recovery is strong at 78%. 7.0h of solid sleep.",
    "data_gaps": [],
    "data_completeness": 0.85,
    "computed_at": "2026-02-09T11:30:00Z",
    "assertions": {
      "dubai_day_valid": true,
      "data_fresh": true,
      "data_sufficient": true,
      "all_passed": true
    }
  },
  "streaks": {
    "water": { "current": 5, "best": 12 },
    "meals": { "current": 3, "best": 8 },
    "weight": { "current": 10, "best": 15 },
    "workout": { "current": 2, "best": 5 }
  },
  "music_today": {
    "tracks_played": 15,
    "total_minutes": 45,
    "unique_artists": 8,
    "top_artist": "Kendrick Lamar",
    "top_album": "GNX"
  },
  "mood_today": {
    "mood_score": 7,
    "energy_score": 6,
    "logged_at": "2026-02-09T09:00:00Z",
    "notes": null
  },
  "bjj_summary": {
    "current_streak": 3,
    "longest_streak": 8,
    "total_sessions": 47,
    "sessions_this_week": 2,
    "sessions_this_month": 6,
    "last_session_date": "2026-02-08"
  },
  "work_summary": {
    "work_date": "2026-02-09",
    "total_minutes": 480,
    "total_hours": 8.0,
    "sessions": 1,
    "first_arrival": "2026-02-09T05:00:00Z",
    "last_departure": "2026-02-09T13:00:00Z",
    "is_at_work": false,
    "current_session_start": null
  },
  "latest_weekly_review": {
    "week_start": "2026-02-03",
    "week_end": "2026-02-09",
    "score": 7,
    "summary_text": "Solid week overall. Recovery averaged 72%...",
    "avg_recovery": 72.3,
    "avg_sleep_hours": 7.2,
    "bjj_sessions": 2,
    "total_spent": 1250.00,
    "habit_completion_pct": 68.5,
    "spending_trend": "stable",
    "recovery_trend": "stable",
    "generated_at": "2026-02-09T08:00:00Z"
  },
  "habits_today": [
    {
      "id": 1,
      "name": "Water",
      "category": "health",
      "frequency": "daily",
      "target_count": 8,
      "icon": "drop.fill",
      "color": "#4FC3F7",
      "completed_today": false,
      "completion_count": 3,
      "current_streak": 5,
      "longest_streak": 12,
      "total_completions": 45,
      "last_7_days": [true, true, true, true, true, false, false]
    }
  ]
}
```

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

### References

| Type | Reference |
|------|-----------|
| iOS Model | `DashboardPayload.swift` |
| n8n Workflow | `dashboard-today-webhook.json` |
| DB Function | `dashboard.get_payload()` (schema v21) |
| Schema | `_schemas/nexus-dashboard-today.json` |
| Migration | `187_habits_system.up.sql` (v21) |

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

