# BJJ Contracts

Brazilian Jiu-Jitsu training session logging and streak tracking.

## POST /webhook/nexus-bjj-log

Log a BJJ/MMA training session. UPSERT by session_date.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |
| Behavior | UPSERT — updates existing session for same date |

### Request

```json
{
  "session_date": "2026-02-09",
  "session_type": "bjj",
  "duration_minutes": 90,
  "start_time": "18:00",
  "end_time": "19:30",
  "techniques": ["armbar", "triangle", "guard passing"],
  "notes": "Focused on closed guard sweeps",
  "source": "manual"
}
```

### Field Definitions

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `session_date` | string (YYYY-MM-DD) | Yes | - | Date of training session |
| `session_type` | string | No | `"bjj"` | One of: `bjj`, `nogi`, `mma` |
| `duration_minutes` | integer | No | `60` | Session duration |
| `start_time` | string (HH:MM) | No | - | Session start time |
| `end_time` | string (HH:MM) | No | - | Session end time |
| `techniques` | string[] | No | - | Techniques practiced |
| `notes` | string | No | - | Free-form notes |
| `source` | string | No | `"manual"` | One of: `manual`, `auto_location`, `auto_whoop`, `notification` |
| `strain` | number | No | - | Whoop strain (auto-populated) |
| `hr_avg` | integer | No | - | Average heart rate (auto-populated) |
| `calories` | integer | No | - | Calories burned (auto-populated) |

### Response

```json
{
  "success": true,
  "session": {
    "id": 1,
    "session_date": "2026-02-09",
    "session_type": "bjj",
    "duration_minutes": 90,
    "start_time": "18:00:00",
    "end_time": "19:30:00",
    "strain": null,
    "hr_avg": null,
    "calories": null,
    "source": "manual",
    "techniques": ["armbar", "triangle", "guard passing"],
    "notes": "Focused on closed guard sweeps",
    "created_at": "2026-02-09T20:00:00Z",
    "updated_at": "2026-02-09T20:00:00Z"
  },
  "is_new": true
}
```

### References

| Type | Reference |
|------|-----------|
| DB Table | `health.bjj_sessions` |
| Migration | `178_bjj_sessions.up.sql` |

### Error Responses

| Code | Condition |
|------|-----------|
| `VALIDATION_ERROR` | Invalid session_type, source, or date format |
| `UNAUTHORIZED` | Missing or invalid API key |
| `INTERNAL_ERROR` | Database error |

---

## GET /webhook/nexus-bjj-history

Retrieve BJJ session history with pagination.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |
| Query Params | `limit` (default 20, max 100), `offset` (default 0) |

### Response

```json
{
  "success": true,
  "sessions": [
    {
      "id": 5,
      "session_date": "2026-02-09",
      "session_type": "bjj",
      "duration_minutes": 90,
      "start_time": "18:00:00",
      "end_time": "19:30:00",
      "strain": 14.2,
      "hr_avg": 142,
      "calories": 650,
      "source": "manual",
      "techniques": ["armbar", "triangle"],
      "notes": "Good rolls today",
      "created_at": "2026-02-09T20:00:00Z",
      "updated_at": "2026-02-09T20:00:00Z"
    },
    {
      "id": 4,
      "session_date": "2026-02-07",
      "session_type": "nogi",
      "duration_minutes": 60,
      "start_time": null,
      "end_time": null,
      "strain": null,
      "hr_avg": null,
      "calories": null,
      "source": "notification",
      "techniques": null,
      "notes": null,
      "created_at": "2026-02-07T19:00:00Z",
      "updated_at": "2026-02-07T19:00:00Z"
    }
  ],
  "count": 2,
  "total": 15,
  "streak": {
    "current_streak": 3,
    "longest_streak": 8
  }
}
```

### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `sessions` | array | Session objects ordered by session_date DESC |
| `count` | integer | Number of sessions in this response |
| `total` | integer | Total sessions in database |
| `streak.current_streak` | integer | Current consecutive weeks with training |
| `streak.longest_streak` | integer | Longest consecutive weeks with training |

### References

| Type | Reference |
|------|-----------|
| DB Table | `health.bjj_sessions` |
| DB Function | `health.get_bjj_streaks()` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## GET /webhook/nexus-bjj-streak

Get BJJ training streak statistics.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |

### Response

```json
{
  "success": true,
  "current_streak": 3,
  "longest_streak": 8,
  "total_sessions": 47,
  "sessions_this_month": 6,
  "sessions_this_week": 2
}
```

### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `current_streak` | integer | Current consecutive weeks with at least one session |
| `longest_streak` | integer | Longest streak of consecutive training weeks |
| `total_sessions` | integer | All-time total sessions |
| `sessions_this_month` | integer | Sessions since start of current month |
| `sessions_this_week` | integer | Sessions since start of current week (Monday) |

### Streak Calculation

A **streak** counts consecutive **weeks** where you trained at least once. Missing a week breaks the streak.

Example:
- Week 1: 3 sessions → streak = 1
- Week 2: 1 session → streak = 2
- Week 3: 0 sessions → streak breaks
- Week 4: 2 sessions → streak = 1 (new)

### References

| Type | Reference |
|------|-----------|
| DB Function | `health.get_bjj_streaks()` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## Data Sources

Sessions can be logged from multiple sources:

| Source | Description |
|--------|-------------|
| `manual` | User manually logs via app |
| `auto_location` | Geo-fence trigger when arriving at gym |
| `auto_whoop` | Matched from Whoop workout with high strain |
| `notification` | Logged via iOS actionable notification |

## Future Enhancements

- Auto-match Whoop workouts to BJJ sessions by time overlap
- Geo-fence integration with gym location
- Technique tracking and progression analytics
- Partner/instructor tracking
- Belt progression milestones
