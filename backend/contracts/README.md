# Nexus API Contracts

> **Single Source of Truth** for all API endpoint contracts.
>
> Last Updated: 2026-02-09 | Schema Version: v17

## Directory Structure

```
backend/contracts/
├── README.md           # This file - index and overview
├── _schemas/           # JSON schemas for automated validation
│   └── *.json
├── dashboard.md        # Dashboard, sleep, sync endpoints
├── finance.md          # Transactions, budgets, recurring, etc.
├── health.md           # Weight, mood, workouts, supplements
├── nutrition.md        # Food logging, water, fasting
├── documents.md        # Document tracking, reminders
├── notes.md            # Obsidian notes index
├── music.md            # Apple Music listening events
├── home.md             # Home Assistant integration
├── receipts.md         # Receipt parsing and nutrition linking
└── architecture.md     # Data flow, ledger, SMS/receipt contracts
```

## Authentication

All endpoints require:
```
Header: X-API-Key: <NEXUS_API_KEY>
```

## Base URL

```
Production: https://n8n.rfanw/webhook/
```

## Quick Reference

| Domain | Endpoints | Primary Tables |
|--------|-----------|----------------|
| [Dashboard](dashboard.md) | 7 | `life.daily_facts`, `dashboard.get_payload()` |
| [Finance](finance.md) | 20 | `finance.transactions`, `finance.budgets` |
| [Health](health.md) | 8 | `health.workouts`, `health.supplements` |
| [Nutrition](nutrition.md) | 10 | `nutrition.food_log`, `nutrition.foods` |
| [Documents](documents.md) | 10 | `life.documents`, `raw.reminders` |
| [Notes](notes.md) | 3 | `raw.notes_index` |
| [Music](music.md) | 2 | `life.listening_events` |
| [Home](home.md) | 2 | N/A (real-time from HA) |
| [Receipts](receipts.md) | 4 | `finance.receipts`, `finance.receipt_items` |

## JSON Schemas

All schemas follow [JSON Schema draft 2020-12](https://json-schema.org/draft/2020-12/schema).

**Response Schemas (17):** Validate API responses
- `nexus-dashboard-today.json`, `nexus-finance-summary.json`, `nexus-budgets.json`
- `nexus-categories.json`, `nexus-monthly-trends.json`, `nexus-recurring.json`, `nexus-rules.json`
- `nexus-food-search.json`, `nexus-health-timeseries.json`, `nexus-sleep.json`, `nexus-sleep-history.json`
- `nexus-documents.json`, `nexus-document-renewals.json`, `nexus-reminders.json`, `nexus-reminders-sync-state.json`
- `nexus-notes-search.json`, `ops-health.json`

**Request Schemas (26):** Validate iOS request bodies
- Finance: `nexus-expense-request.json`, `nexus-transaction-request.json`, `nexus-update-transaction-request.json`, `nexus-income-request.json`, `nexus-budgets-request.json`, `nexus-recurring-request.json`, `nexus-create-correction-request.json`
- Health: `nexus-weight-request.json`, `nexus-mood-request.json`, `nexus-universal-request.json`, `nexus-workout-request.json`, `nexus-supplement-request.json`, `nexus-supplement-log-request.json`
- Nutrition: `nexus-food-log-request.json`, `nexus-water-request.json`, `nexus-meal-confirmation-request.json`
- Documents: `nexus-document-request.json`, `nexus-document-update-request.json`, `nexus-document-renew-request.json`, `nexus-document-recreate-reminders-request.json`, `nexus-reminder-create-request.json`, `nexus-reminder-update-request.json`, `nexus-reminder-delete-request.json`
- Other: `nexus-music-events-request.json`, `nexus-home-control-request.json`, `nexus-receipt-item-match-request.json`

## Validation

Run contract validation:
```bash
# Validate response against schema
./ops/lib/validate-contract.sh backend/contracts/_schemas/nexus-dashboard-today.json <response.json>

# Test all endpoints
python backend/scripts/test_contracts.py
```

## Response Format

All endpoints return:
```json
{
  "success": true,
  "data": { ... },
  "error": null
}
```

## Error Response Contract

All error responses follow this shape:
```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable message"
  }
}
```

### Standard Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `VALIDATION_ERROR` | 400 | Request body or query params failed validation |
| `UNAUTHORIZED` | 401 | Missing or invalid X-API-Key header |
| `NOT_FOUND` | 404 | Requested resource does not exist |
| `CONFLICT` | 409 | Operation conflicts with current state (e.g., duplicate) |
| `RATE_LIMITED` | 429 | Too many requests, retry after backoff |
| `INTERNAL_ERROR` | 500 | Unexpected server error |

## DELETE Semantics

| Endpoint | Type | Behavior |
|----------|------|----------|
| `DELETE /nexus-delete-transaction` | **HARD** | Permanently removes row from `finance.transactions` |
| `DELETE /nexus-document` | Soft | Sets `deleted_at = NOW()`, `status = 'expired'` |
| `DELETE /nexus-recurring` | Soft | Sets `is_active = false` |
| `POST /nexus-reminder-delete` | Soft | Sets `deleted_at`, `sync_status = 'deleted_local'` |
| `DELETE /nexus-note-delete` | Soft | Sets `deleted_at = NOW()` (Obsidian file unchanged) |

**Note**: Transaction delete is the only hard delete. All others preserve data for recovery.

## Idempotency

### Summary by Pattern

| Pattern | Used By | Behavior |
|---------|---------|----------|
| `client_id` UUID | Transactions, expenses, income, documents | `ON CONFLICT DO NOTHING` |
| `external_id` | HealthKit workouts | Dedup via trigger |
| `(session_id, started_at)` | Music listening events | `ON CONFLICT DO NOTHING` |
| `(month, category)` | Budgets | `ON CONFLICT DO UPDATE` |
| `(recorded_at, source, metric_type)` | Weight, health metrics | `ON CONFLICT DO UPDATE` |
| `(supplement_id, date, time_slot)` | Supplement logs | UPSERT via trigger |

### Full Mutation Reference

| Endpoint | Method | Idempotency Key | On Duplicate |
|----------|--------|-----------------|--------------|
| **Finance** |
| `/nexus-expense` | POST | `client_id` | IGNORE |
| `/nexus-transaction` | POST | `client_id` | IGNORE |
| `/nexus-income` | POST | `client_id` | IGNORE |
| `/nexus-update-transaction` | POST | ID lookup | N/A (update) |
| `/nexus-delete-transaction` | DELETE | ID lookup | N/A (delete) |
| `/nexus-budgets` | POST | `(month, category)` | UPDATE |
| `/nexus-recurring` | POST | **NONE** | ERROR |
| `/nexus-create-correction` | POST | **NONE** | INSERT always |
| **Health** |
| `/nexus-weight` | POST | `(recorded_at, source, metric_type)` | UPDATE |
| `/nexus-mood` | POST | `(date)` implicit | Aggregates |
| `/nexus-workout` | POST | `external_id` | Dedup via trigger |
| `/nexus-supplement` | POST | ID (if provided) | UPSERT |
| `/nexus-supplement-log` | POST | `(supplement_id, date, time_slot)` | UPSERT |
| **Documents & Reminders** |
| `/nexus-document` | POST | `client_id` | IGNORE |
| `/nexus-document-update` | POST | ID lookup | N/A (update) |
| `/nexus-document-renew` | POST | ID lookup | N/A (update) |
| `/nexus-reminder-create` | POST | **NONE** | INSERT always |
| `/nexus-reminder-update` | POST | ID lookup | N/A (update) |
| `/nexus-reminder-delete` | POST | ID lookup | N/A (delete) |
| **Nutrition** |
| `/nexus-food-log` | POST | **NONE** | INSERT always |
| `/nexus-water` | POST | **NONE** | INSERT always |
| `/nexus-fast-start` | POST | Active session check | ERROR if active |
| `/nexus-fast-break` | POST | Active session lookup | ERROR if none |
| `/nexus-meal-confirmation` | POST | ID lookup | N/A (update) |
| **Music** |
| `/nexus-music-events` | POST | `(session_id, started_at)` | IGNORE |
| **Receipts** |
| `/nexus-receipt-item-match` | POST | ID lookup | N/A (update) |
| **Notes** |
| `/nexus-note-update` | PUT | ID lookup | N/A (update) |
| `/nexus-note-delete` | DELETE | ID lookup | N/A (delete) |

**Legend**:
- **IGNORE**: Duplicate silently ignored, returns success
- **UPDATE**: Duplicate updates existing record
- **ERROR**: Duplicate returns 409 Conflict
- **NONE**: No protection, duplicates inserted (use caution with retries)

## Changelog

| Date | Change |
|------|--------|
| 2026-02-09 | Added DELETE semantics (soft vs hard) and full idempotency specs for all mutation endpoints |
| 2026-02-09 | Schema v17: Added `deep_sleep_minutes`, `rem_sleep_minutes` to dashboard today_facts (was missing from API) |
| 2026-02-09 | **JSON Schema rewrite**: Rewrote all 17 response schemas to JSON Schema draft 2020-12; created 26 new request schemas for POST/PUT/DELETE endpoints |
| 2026-02-09 | Added Error Response Contract with standard error codes; added Error Responses to all endpoints |
| 2026-02-09 | Path alignment: iOS `nexus-summary` → `nexus-dashboard-today`; contracts updated for `nexus-fast-*`, `nexus-supplement`, `nexus-create-correction` |
| 2026-02-09 | Consolidated contracts into single directory |
| 2026-02-08 | Added financial-position endpoint |
| 2026-02-06 | Dashboard schema v16, explain_today |

---

*Maintained by Claude Code agents. Update contracts before implementing new endpoints.*
