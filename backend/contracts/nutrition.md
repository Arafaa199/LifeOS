# Nutrition Contracts

## POST /webhook/nexus-food-log

Logs food via natural language or food ID.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "text": "Grilled chicken salad 450 calories",
  "source": "ios",
  "food_id": null,
  "meal_type": "lunch"
}
```

### Response

```json
{
  "success": true,
  "data": {
    "calories": 450,
    "protein": 35.0
  }
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `NexusModels.swift` → `FoodLogRequest`, `NexusResponse` |
| n8n Workflow | `food-log-webhook.json` |
| DB Table | `nutrition.food_log` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `INTERNAL_ERROR`

---

## GET /webhook/nexus-food-search

Searches food database.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |
| Query Params | `q` (search query), `limit` (default 20), OR `barcode` |

### Response

```json
{
  "success": true,
  "count": 15,
  "data": [
    {
      "id": 12345,
      "fdc_id": 167512,
      "barcode": null,
      "name": "Chicken Breast",
      "brand": "Generic",
      "source": "usda",
      "calories_per_100g": 165,
      "protein_per_100g": 31,
      "carbs_per_100g": 0,
      "fat_per_100g": 3.6,
      "fiber_per_100g": 0,
      "serving_size_g": 100,
      "serving_description": "100g",
      "category": "Poultry",
      "data_quality": 5,
      "relevance": 0.95
    }
  ]
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `NexusModels.swift` → `FoodSearchResponse`, `FoodSearchResult` |
| n8n Workflow | `food-search-webhook.json` |
| DB Table | `nutrition.foods` |
| DB Function | `nutrition.search_foods()`, `nutrition.lookup_barcode()` |
| Schema | `_schemas/nexus-food-search.json` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## GET /webhook/nexus-nutrition-history

Fetches nutrition log for a date.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |
| Query Params | `date` (YYYY-MM-DD) |

### Response

```json
{
  "success": true,
  "date": "2026-02-08",
  "food_log": [
    {
      "id": 1,
      "description": "Chicken salad",
      "meal_time": "lunch",
      "calories": 450,
      "protein_g": 35,
      "carbs_g": 20,
      "fat_g": 15,
      "source": "manual",
      "confidence": "high",
      "logged_at": "2026-02-08T12:30:00Z"
    }
  ],
  "water_log": [
    {
      "id": 1,
      "amount_ml": 500,
      "logged_at": "2026-02-08T09:00:00Z"
    }
  ],
  "totals": {
    "calories": 1800,
    "protein_g": 120,
    "carbs_g": 150,
    "fat_g": 60,
    "water_ml": 2500,
    "meals_logged": 3
  }
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `NexusModels.swift` → `NutritionHistoryResponse`, `FoodLogEntry`, `WaterLogEntry` |
| n8n Workflow | `nutrition-history-webhook.json` |
| DB Tables | `nutrition.food_log`, `nutrition.water_log` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-water

Logs water intake.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "amount_ml": 500
}
```

### Validation

- `amount_ml`: 1-10000

### Response

```json
{
  "success": true,
  "data": {
    "id": 5,
    "amount_ml": 500,
    "total_water_ml": 2000
  }
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `NexusModels.swift` → `WaterLogRequest`, `WaterLogResponse` |
| n8n Workflow | `nexus-universal-webhook.json` |
| DB Table | `nutrition.water_log` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-fast-start

Starts a fasting session.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |
| Body | None |

### Response

```json
{
  "success": true,
  "session_id": 5,
  "started_at": "2026-02-08T20:00:00Z"
}
```

### Idempotency

Only one active session allowed at a time.

### References

| Type | Reference |
|------|-----------|
| iOS Model | `NexusModels.swift` → `FastingResponse` |
| n8n Workflow | `fasting-webhook.json` |
| DB Table | `health.fasting_sessions` |

### Error Responses

`UNAUTHORIZED`, `CONFLICT`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-fast-break

Breaks the current fasting session.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |
| Body | None |

### Response

```json
{
  "success": true,
  "session_id": 5,
  "duration_hours": 16.5,
  "started_at": "2026-02-08T20:00:00Z",
  "ended_at": "2026-02-09T12:30:00Z"
}
```

### Error Responses

`UNAUTHORIZED`, `CONFLICT`, `INTERNAL_ERROR`

### References

| Type | Reference |
|------|-----------|
| iOS Model | `NexusModels.swift` → `FastingResponse` |
| n8n Workflow | `fasting-webhook.json` |
| DB Table | `health.fasting_sessions` |

---

## GET /webhook/nexus-fast-status

Gets current fasting status.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |

### Response

```json
{
  "success": true,
  "is_active": true,
  "session_id": 5,
  "started_at": "2026-02-08T20:00:00Z",
  "elapsed_hours": 8.5
}
```

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

### References

| Type | Reference |
|------|-----------|
| iOS Model | `NexusModels.swift` → `FastingResponse` |
| n8n Workflow | `fasting-webhook.json` |
| DB Table | `health.fasting_sessions` |

---

## GET /webhook/nexus-pending-meals

Fetches unconfirmed meals needing review.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |

### Response

```json
{
  "success": true,
  "pending": [
    {
      "id": 123,
      "description": "Chicken salad",
      "calories": 450,
      "confidence": "low",
      "logged_at": "2026-02-08T12:30:00Z"
    }
  ]
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `NutritionAPI.swift` → `fetchPendingMeals()` |
| n8n Workflow | `pending-meals-webhook.json` |
| DB Table | `nutrition.food_log` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-meal-confirmation

Confirms or adjusts a pending meal.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "meal_id": 123,
  "confirmed": true,
  "adjusted_calories": 500
}
```

### Response

```json
{
  "success": true,
  "message": "Meal confirmed"
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `NutritionAPI.swift` → `confirmMeal()` |
| n8n Workflow | `meal-confirmation-webhook.json` |
| DB Table | `nutrition.food_log` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `NOT_FOUND`, `INTERNAL_ERROR`

---

## Notes

1. **Schema location**: `fasting_sessions` is in `health` schema, not `nutrition`
