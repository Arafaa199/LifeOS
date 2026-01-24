# Nexus n8n Workflows

## Prerequisites

1. **PostgreSQL Credential** (ID: `p5cyLWCZ9Db6GiiQ`):
   - Host: `nexus` (or 100.90.189.16)
   - Port: `5432`
   - Database: `nexus`
   - User: `nexus`
   - Password: (from `.env`)

2. **Home Assistant Credential**: HTTP Header Auth with HA token

## Workflows

### Health Data

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `health-metrics-sync.json` | Every 15 min | Polls HA for WHOOP data → `health.metrics` |
| `sleep-fetch-webhook.json` | GET `/webhook/nexus-sleep` | Returns sleep/recovery for date |
| `weight-log-webhook.json` | POST `/webhook/nexus-weight` | Logs weight from iOS HealthKit |
| `mood-log-webhook.json` | POST `/webhook/nexus-mood` | Logs mood/energy (1-10 scale) |
| `workout-log-webhook.json` | POST `/webhook/nexus-workout` | Logs workout data |

### Nutrition

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `food-log-webhook.json` | POST `/webhook/nexus-food` | Text-based food logging |
| `photo-food-webhook.json` | POST `/webhook/nexus-photo-food` | Claude Vision food analysis |
| `water-log-webhook.json` | POST `/webhook/nexus-water` | Water intake logging |

### Finance

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `expense-log-webhook.json` | POST `/webhook/nexus-expense` | Quick expense ("$45 groceries") |
| `finance-summary-webhook.json` | GET `/webhook/nexus-finance-summary` | Daily/monthly summary |
| `budget-webhook.json` | Various | Budget CRUD operations |

### System

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `daily-summary-update.json` | Midnight | Aggregates data to `core.daily_summary` |

## Webhook Endpoints

```
# Health
GET  /webhook/nexus-sleep?date=2026-01-21    # WHOOP sleep/recovery
GET  /webhook/nexus-sleep-history?days=7     # Sleep history
POST /webhook/nexus-weight                    # Weight from HealthKit
POST /webhook/nexus-mood                      # Mood/energy logging
POST /webhook/nexus-workout                   # Workout logging

# Nutrition
POST /webhook/nexus-food                      # Food logging
POST /webhook/nexus-water                     # Water logging
POST /webhook/nexus-photo-food                # Photo food (Claude Vision)

# Finance
POST /webhook/nexus-expense                   # Quick expense
POST /webhook/nexus-transaction               # Full transaction
GET  /webhook/nexus-finance-summary           # Finance overview
GET  /webhook/nexus-budgets                   # Budget list
```

## Import Instructions

1. Open n8n at https://n8n.rfanw
2. Workflows → Import from File
3. Select JSON file
4. **Update credentials** in Postgres nodes
5. Toggle active off/on to register webhooks
6. Activate

## Testing

```bash
# Test weight webhook
curl -X POST https://n8n.rfanw/webhook/nexus-weight \
  -H "Content-Type: application/json" \
  -d '{"weight_kg": 75.5}'

# Test sleep fetch
curl "https://n8n.rfanw/webhook/nexus-sleep?date=2026-01-21"

# Test expense
curl -X POST https://n8n.rfanw/webhook/nexus-expense \
  -H "Content-Type: application/json" \
  -d '{"text": "coffee 15 AED"}'
```

## Health Data Flow

```
WHOOP → Home Assistant (HACS) → health-metrics-sync (15 min poll) → health.metrics
                                                                          ↑
Eufy Scale → Apple Health → iOS App (HealthKitManager) → /webhook/nexus-weight
```

**Key WHOOP sensors polled**:
- `sensor.whoop_ahmed_recovery_score`
- `sensor.whoop_ahmed_hrv`
- `sensor.whoop_ahmed_resting_heart_rate`
- `sensor.whoop_ahmed_day_strain`
- `sensor.whoop_ahmed_sleep_performance`
- `sensor.whoop_ahmed_sleep_sws_time` (deep sleep)
