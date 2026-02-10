# n8n Deployment Runbook

## Prerequisites

- SSH access: `ssh pivpn`
- n8n UI: https://n8n.rfanw
- API Key: stored in `~/.n8n-api-key` on server
- Workflows dir: `~/LifeOS/backend/n8n-workflows/`

## Step 1: Verify n8n is Running

```bash
ssh pivpn
docker ps | grep n8n
# Should show n8n container running
```

## Step 2: Set Required Environment Variables

These must be set inside the n8n Docker container. Check current state:

```bash
docker exec n8n env | grep -E "HOME_ASSISTANT|NEXUS_SCRIPTS|MAILHOG|TELEGRAM"
```

If missing, add them to your Docker run command or docker-compose.yml:

| Variable | Example Value | Used By |
|----------|---------------|---------|
| `HOME_ASSISTANT_URL` | `http://100.90.189.16:8123` | HA metrics sync, home control |
| `NEXUS_SCRIPTS_DIR` | `/home/rafa/LifeOS/backend/scripts` | SMS import, resolve-events |
| `MAILHOG_URL` | `http://localhost:8025` | Weekly insight report |
| `TELEGRAM_BOT_TOKEN` | *(your bot token)* | DLQ alerts, notifications |
| `TELEGRAM_CHAT_ID` | *(your chat ID)* | DLQ alerts, notifications |

To set permanently in Docker:

```bash
# Stop n8n
docker stop n8n

# Restart with env vars (add to your existing docker run command)
docker run -d --name n8n \
  -e HOME_ASSISTANT_URL="http://100.90.189.16:8123" \
  -e NEXUS_SCRIPTS_DIR="/home/rafa/LifeOS/backend/scripts" \
  -e MAILHOG_URL="http://localhost:8025" \
  -e TELEGRAM_BOT_TOKEN="your-token" \
  -e TELEGRAM_CHAT_ID="your-chat-id" \
  ... (rest of your existing flags)
```

## Step 3: Import All Workflows

From your server:

```bash
cd ~/LifeOS/backend/scripts
API_KEY=$(cat ~/.n8n-api-key)  # or paste directly
bash import-workflows-simple.sh "$API_KEY"
```

This imports 57 workflows across 7 categories:
- Finance (12): expense, income, transactions, budgets, insights, SMS
- Health & Nutrition (14): food, weight, sleep, workouts, supplements, fasting
- Medications (4): batch sync, toggle, create (NEW), calendar sync
- Documents & Notes (4): CRUD, notes index (fixes 404), update/delete (NEW)
- Receipts (3): CRUD, email ingest, batch import (NEW)
- Dashboard & System (12): dashboard, summaries, calendar, reminders, events
- Infrastructure (8): HA metrics, home control, DLQ monitor (NEW), DLQ retry/cleanup

## Step 4: Verify Active Workflows

```bash
sqlite3 ~/n8n-data/database.sqlite \
  "SELECT id, name, active FROM workflow_entity WHERE active = 1 ORDER BY name;"
```

Expected: ~57 active workflows.

## Step 5: Disable Deprecated Duplicates

If any `with-auth/` workflows got imported previously, disable them:

```bash
# List potential duplicates
sqlite3 ~/n8n-data/database.sqlite \
  "SELECT id, name FROM workflow_entity WHERE name LIKE '%DEPRECATED%' AND active = 1;"

# Disable via API
curl -s -X PATCH \
  -H "X-N8N-API-KEY: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"active": false}' \
  "https://n8n.rfanw/api/v1/workflows/<ID>"
```

Deprecated workflows to disable if found:
- `[DEPRECATED] Nexus: Daily Summary API - Auth Version`
- `[DEPRECATED] Nexus: Daily Life Summary API`
- `[DEPRECATED] Nexus: Daily Summary Update`

## Step 6: Quick Smoke Test

From your Mac (or any machine on Tailscale):

```bash
# Dashboard endpoint
curl -s https://n8n.rfanw/webhook/nexus-today | jq '.success'

# Notes endpoint (was 404)
curl -s https://n8n.rfanw/webhook/nexus-notes-index | jq '.success'

# New medication create (should return validation error with empty body)
curl -s -X POST https://n8n.rfanw/webhook/nexus-medication-create \
  -H "Content-Type: application/json" -d '{}' | jq '.error'
```

## Step 7: Verify from iOS App

1. Open Nexus app
2. Check Notes tab → should load (no more 404)
3. Check Medications → tap + to add → should work
4. Check Supplements → should load without crash
5. Pull-to-refresh on Dashboard → weight should show recent value

## Webhook Path Reference (New Endpoints)

| Path | Method | Description |
|------|--------|-------------|
| `nexus-medication-create` | POST | Create new medication |
| `nexus-receipt-batch-import` | POST | Batch import old receipts |
| `nexus-note-update` | PUT | Update note content |
| `nexus-note-delete` | DELETE | Soft-delete a note |
| `nexus-notes-index` | GET | List all notes (fixes 404) |

## Duplicate Webhook Paths (Do NOT Import)

These files exist on disk as development iterations but should NOT be imported (only one per path should be active):

- `income-webhook-simple.json` → same path as `income-webhook.json`
- `income-webhook-validated.json` → same path as `income-webhook.json`
- `income-webhook-canonical.json` → same path as `income-webhook.json`
- `with-auth/*.json` → older auth-wrapped versions, all deprecated

## Troubleshooting

**Workflow import fails with "duplicate" error:**
The import script handles this — it updates existing workflows by name.

**Webhook returns 404:**
Check the workflow is active: `sqlite3 ~/n8n-data/database.sqlite "SELECT active FROM workflow_entity WHERE name LIKE '%Notes%';"`

**Environment variable not resolving:**
Check inside container: `docker exec n8n printenv | grep HOME_ASSISTANT`

**DLQ alerts not firing:**
Verify Telegram credentials: `docker exec n8n printenv | grep TELEGRAM`
