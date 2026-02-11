# Habits Contracts

Daily habit tracking with streaks and 7-day completion history.

## GET /webhook/nexus-habits

Fetch all active habits with today's completion status and streaks.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |
| Query Params | None |

### Response

```json
{
  "success": true,
  "habits": [
    {
      "id": 1,
      "name": "Water",
      "category": "health",
      "frequency": "daily",
      "target_count": 8,
      "icon": "drop.fill",
      "color": "#4FC3F7",
      "is_active": true,
      "completed_today": false,
      "completion_count": 3,
      "current_streak": 5,
      "longest_streak": 12,
      "total_completions": 45,
      "last_7_days": [true, true, true, true, true, false, false]
    }
  ],
  "count": 5
}
```

### Field Definitions

| Field | Type | Description |
|-------|------|-------------|
| `id` | integer | Habit ID |
| `name` | string | Habit name |
| `category` | string | One of: `health`, `fitness`, `productivity`, `mindfulness` |
| `frequency` | string | Currently only `daily` |
| `target_count` | integer | Completions needed per day (e.g. 8 for water glasses) |
| `icon` | string | SF Symbol name |
| `color` | string | Hex color code |
| `completed_today` | boolean | `completion_count >= target_count` |
| `completion_count` | integer | Today's completion count |
| `current_streak` | integer | Consecutive days completed (from today backwards) |
| `longest_streak` | integer | All-time longest streak |
| `total_completions` | integer | All-time total completions |
| `last_7_days` | boolean[] | 7 elements, index 0 = 6 days ago, index 6 = today |

### References

| Type | Reference |
|------|-----------|
| DB Function | `life.get_habits_today()` |
| DB Table | `life.habits`, `life.habit_completions` |
| n8n Workflow | `habits-webhooks.json` |
| Migration | `187_habits_system.up.sql` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-habit-complete

Log a habit completion for today. UPSERT by habit_id + date.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "habit_id": 1,
  "count": 1,
  "notes": "Morning glass"
}
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `habit_id` | integer | Yes | - | ID of the habit to complete |
| `count` | integer | No | `1` | Number of completions |
| `notes` | string | No | `null` | Optional note |

### Response

```json
{
  "success": true,
  "habit": {
    "id": 1,
    "name": "Water",
    "category": "health",
    "frequency": "daily",
    "target_count": 8,
    "icon": "drop.fill",
    "color": "#4FC3F7",
    "is_active": true,
    "completed_today": false,
    "completion_count": 4,
    "current_streak": 5,
    "longest_streak": 12,
    "total_completions": 46,
    "last_7_days": [true, true, true, true, true, false, false]
  }
}
```

### References

| Type | Reference |
|------|-----------|
| DB Table | `life.habit_completions` |
| DB Constraint | UPSERT on `(habit_id, date)` |
| n8n Workflow | `habits-webhooks.json` |

### Error Responses

| Code | Condition |
|------|-----------|
| `VALIDATION_ERROR` | Missing or invalid `habit_id` |
| `UNAUTHORIZED` | Missing or invalid API key |
| `INTERNAL_ERROR` | Database error |

---

## POST /webhook/nexus-habit-create

Create a new habit.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "name": "Meditation",
  "category": "mindfulness",
  "frequency": "daily",
  "target_count": 1,
  "icon": "brain.head.profile",
  "color": "#AB47BC"
}
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | string | Yes | - | Habit name |
| `category` | string | No | `null` | One of: `health`, `fitness`, `productivity`, `mindfulness` |
| `frequency` | string | No | `daily` | Currently only `daily` |
| `target_count` | integer | No | `1` | Completions per day |
| `icon` | string | No | `null` | SF Symbol name |
| `color` | string | No | `null` | Hex color code |

### Response

```json
{
  "success": true,
  "habit": {
    "id": 6,
    "name": "Meditation",
    "category": "mindfulness",
    "frequency": "daily",
    "target_count": 1,
    "icon": "brain.head.profile",
    "color": "#AB47BC",
    "is_active": true,
    "completed_today": false,
    "completion_count": 0,
    "current_streak": 0,
    "longest_streak": 0,
    "total_completions": 0,
    "last_7_days": [false, false, false, false, false, false, false]
  }
}
```

### Error Responses

| Code | Condition |
|------|-----------|
| `VALIDATION_ERROR` | Missing `name` |
| `UNAUTHORIZED` | Missing or invalid API key |
| `INTERNAL_ERROR` | Database error |

---

## DELETE /webhook/nexus-habit-delete

Soft-delete (deactivate) a habit. Sets `is_active = false`.

| Field | Value |
|-------|-------|
| Method | DELETE |
| Auth | X-API-Key header |
| Query Params | `id` (habit ID) |

### Response

```json
{
  "success": true,
  "message": "Habit deactivated",
  "id": 6
}
```

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## Dashboard Integration

Habits are included in `dashboard.get_payload()` as the `habits_today` array (schema v21, migration 187).

## Seed Habits

| Name | Category | Target | Icon |
|------|----------|--------|------|
| Water | health | 8 | `drop.fill` |
| BJJ Training | fitness | 1 | `figure.martial.arts` |
| Supplements | health | 1 | `leaf.fill` |
| Weight Log | health | 1 | `scalemass` |
| Meal Log | health | 1 | `fork.knife` |
