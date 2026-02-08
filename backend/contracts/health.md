# Health Contracts

## POST /webhook/nexus-weight

Logs weight measurement.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "weight_kg": 75.5
}
```

### Response

```json
{
  "success": true,
  "data": {
    "weight_kg": 75.5
  }
}
```

### Idempotency

UPSERT by date - only one weight per day.

### References

| Type | Reference |
|------|-----------|
| iOS Model | `NexusModels.swift` → `WeightLogRequest`, `NexusResponse` |
| n8n Workflow | `weight-log-webhook.json` |
| DB Table | `health.metrics` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-mood

Logs mood and energy levels.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "mood": 7,
  "energy": 6,
  "notes": "Feeling good after workout"
}
```

### Response

```json
{
  "success": true,
  "message": "Mood logged"
}
```

### Validation

- `mood`: 1-10
- `energy`: 1-10

### References

| Type | Reference |
|------|-----------|
| iOS Model | `NexusModels.swift` → `MoodLogRequest` |
| n8n Workflow | `nexus-universal-webhook.json` |
| DB Table | `health.mood_log` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-universal

Universal natural language health/wellness logging.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "text": "Weight 75.5kg, feeling good today",
  "source": "ios",
  "context": "auto"
}
```

### Response

```json
{
  "success": true,
  "data": {
    "weight_kg": 75.5
  }
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `NexusModels.swift` → `UniversalLogRequest`, `NexusResponse` |
| n8n Workflow | `nexus-universal-webhook.json` |
| DB Table | Multiple (routed by content) |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `INTERNAL_ERROR`

---

## GET /webhook/nexus-workouts

Fetches recent workouts with weekly stats.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |

### Response

```json
{
  "workouts": [
    {
      "id": 1,
      "date": "2026-02-08",
      "workout_type": "strength",
      "name": "Upper Body",
      "duration_min": 45,
      "calories_burned": 350,
      "avg_hr": 135,
      "max_hr": 165,
      "strain": 12.5,
      "source": "apple_watch"
    }
  ],
  "weekly_stats": {
    "workout_count": 4,
    "total_duration": 180,
    "total_calories": 1400,
    "avg_strain": 11.2
  },
  "whoop_today": {
    "day_strain": 12.5,
    "avg_hr": 72,
    "max_hr": 165,
    "calories_active": 450
  }
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `WorkoutModels.swift` → `WorkoutsResponse`, `Workout` |
| n8n Workflow | `workouts-fetch-webhook.json` |
| DB Table | `health.workouts` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-workout

Logs a workout.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "date": "2026-02-08",
  "workout_type": "strength",
  "name": "Upper body",
  "duration_min": 45,
  "calories_burned": 350,
  "avg_hr": 135,
  "max_hr": 165,
  "strain": null,
  "exercises": [
    { "name": "Bench Press", "sets": 4, "reps": 8, "weight": 60, "weight_unit": "kg" }
  ],
  "distance_km": null,
  "notes": "Good session",
  "source": "manual",
  "started_at": "2026-02-08T10:00:00Z",
  "ended_at": "2026-02-08T10:45:00Z",
  "external_id": "healthkit-uuid"
}
```

### Response

```json
{
  "success": true,
  "data": {
    "workout": { "id": 5, ... },
    "weekly_stats": { "workout_count": 4, ... }
  }
}
```

### Idempotency

`external_id` (HealthKit UUID) — Deduplication via database trigger. Duplicate `external_id` values are silently ignored.

### References

| Type | Reference |
|------|-----------|
| iOS Model | `WorkoutModels.swift` → `WorkoutLogRequest`, `WorkoutLogResponse` |
| n8n Workflow | `workout-log-webhook.json` |
| DB Table | `health.workouts` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `CONFLICT`, `INTERNAL_ERROR`

---

## GET /webhook/nexus-supplements

Fetches supplements with today's dose status.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |

### Response

```json
{
  "supplements": [
    {
      "id": 1,
      "name": "Vitamin D3",
      "brand": "NOW Foods",
      "dose_amount": 5000,
      "dose_unit": "IU",
      "frequency": "daily",
      "times_of_day": ["morning"],
      "category": "vitamin",
      "active": true,
      "today_doses": [
        { "time_slot": "morning", "status": "taken" }
      ]
    }
  ],
  "summary": {
    "total_supplements": 5,
    "total_doses_today": 7,
    "taken": 5,
    "skipped": 0,
    "pending": 2,
    "adherence_pct": 71
  }
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `SupplementModels.swift` → `SupplementsResponse`, `Supplement` |
| n8n Workflow | `supplements-webhook.json` |
| DB Table | `health.supplements`, `health.supplement_log` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-supplement-log

Logs supplement intake.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "supplement_id": 1,
  "status": "taken",
  "time_slot": "morning",
  "notes": null
}
```

### Response

```json
{
  "success": true,
  "medication_id": 1,
  "summary": {
    "taken_today": 5,
    "skipped_today": 0,
    "pending_today": 2
  }
}
```

### Idempotency

UPSERT by (supplement_id, date, time_slot).

### References

| Type | Reference |
|------|-----------|
| iOS Model | `SupplementModels.swift` → `SupplementLogRequest`, `SupplementLogResponse` |
| n8n Workflow | `supplement-log-webhook.json` |
| DB Table | `health.supplement_log` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `NOT_FOUND`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-supplement

Creates or updates a supplement (UPSERT).

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "name": "Omega 3",
  "brand": "Nordic Naturals",
  "dose_amount": 1000,
  "dose_unit": "mg",
  "frequency": "daily",
  "times_of_day": ["morning", "evening"],
  "category": "supplement",
  "notes": "Take with food"
}
```

For updates, include `id`:

```json
{
  "id": 6,
  "name": "Omega 3",
  "active": false
}
```

### Response

```json
{
  "success": true,
  "action": "created",
  "supplement": { "id": 6, ... }
}
```

### Idempotency

UPSERT by id (if provided) or insert new.

### References

| Type | Reference |
|------|-----------|
| iOS Model | `SupplementModels.swift` → `SupplementCreateRequest`, `SupplementUpsertResponse` |
| n8n Workflow | `supplements-webhook.json` |
| DB Table | `health.supplement_definitions` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `INTERNAL_ERROR`
