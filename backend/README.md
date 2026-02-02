# Nexus - Personal Life Data Hub

Unified PostgreSQL database consolidating health, nutrition, finance, and notes data for Claude-powered insights and n8n automation.

## Quick Start

```bash
# 1. Copy to server
scp -r ~/Cyber/Infrastructure/Nexus-setup nexus:/tmp/

# 2. SSH and run setup
ssh nexus
cd /tmp/Nexus-setup
sudo ./setup.sh

# 3. Save the generated password!
```

## Directory Structure

```
Nexus-setup/
├── docker-compose.yml      # Postgres + NocoDB + optional pgAdmin
├── init.sql                # Complete schema (6 schemas, 20+ tables)
├── setup.sh                # One-command deployment with validation
├── backup.sh               # Backups with remote sync & notifications
├── restore.sh              # Safe restore with pre-restore backup
├── healthcheck.sh          # Health monitoring (text/JSON output)
├── .env.example            # Configuration template
├── MIGRATION.md            # Move to new machine guide
├── README.md               # This file
├── config/
│   ├── caddy-snippet.conf  # Reverse proxy config for Caddy
│   └── ha-package-nexus.yaml  # Home Assistant package
└── n8n-workflows/
    ├── README.md           # Workflow documentation
    ├── daily-summary-update.json
    ├── food-log-webhook.json
    └── health-metrics-sync.json
```

## Services

| Service | Port | URL |
|---------|------|-----|
| PostgreSQL | 5432 | `postgresql://nexus:PASSWORD@HOST:5432/nexus` |
| NocoDB | 8080 | https://nexus.rfanw |
| pgAdmin (optional) | 5050 | Start with `--profile admin` |

## Database Schema

Single-pipeline architecture: **Source → raw → normalized → life.daily_facts**

```
nexus/
├── raw/            → whoop_recovery, whoop_sleep, bank_sms, calendar_events, reminders, notes_index
├── normalized/     → daily_recovery, daily_sleep, daily_strain, body_metrics, food_log, v_daily_finance (VIEW)
├── life/           → daily_facts (canonical dashboard), documents, document_reminders, behavioral_events, locations
├── finance/        → transactions, categories (16), recurring_items, merchant_rules (120+), budgets, mv_monthly_spend
├── health/         → whoop_recovery, whoop_sleep, whoop_strain, metrics (trigger → raw → normalized)
├── nutrition/      → foods (2.4M rows), food_log, daily_targets
├── ops/            → refresh_log, rebuild_runs, trigger_errors
├── insights/       → correlations, anomalies, pattern_detector
└── dashboard/      → (views for aggregated display)
```

See `LifeOS_Technical_Documentation.md` at the repo root for full details.

## Commands

```bash
# View logs
cd /var/www/nexus && docker compose logs -f

# Backup
sudo ./backup.sh

# Restore
sudo ./restore.sh /path/to/backup.sql.gz

# Health check (text)
./healthcheck.sh

# Health check (JSON for n8n)
./healthcheck.sh json

# Start pgAdmin
docker compose --profile admin up -d

# Access psql
docker exec -it nexus-db psql -U nexus nexus
```

## n8n Integration

1. Create PostgreSQL credential in n8n:
   ```
   Host: nexus (or IP)
   Port: 5432
   Database: nexus
   User: nexus
   Password: (from /var/www/nexus/.env)
   ```

2. Import workflows from `n8n-workflows/`:
   - **Daily Summary Update**: Aggregates data nightly
   - **Food Log Webhook**: `POST /webhook/nexus-food-log`
   - **Health Metrics Sync**: Pulls from Home Assistant every 15min

## Home Assistant Integration

Copy `config/ha-package-nexus.yaml` to your HA packages directory:

```bash
scp config/ha-package-nexus.yaml pivpn:~/HomeAssistant/packages/nexus.yaml
```

Provides sensors:
- `sensor.nexus_calories_today`
- `sensor.nexus_protein_today`
- `sensor.nexus_database_size`
- `binary_sensor.nexus_database_online`
- And more...

## Backup Features

- **Integrity verification**: Validates gzip and table count
- **Remote sync**: Copies to NAS (configure in `.env`)
- **Notifications**: Email alerts on success/failure
- **Retention**: Keeps last 7 backups automatically
- **Pre-restore safety**: Creates backup before any restore

Enable remote backup in `.env`:
```bash
REMOTE_BACKUP_ENABLED=true
REMOTE_BACKUP_HOST=nas
REMOTE_BACKUP_PATH=/Volume2/Backups/nexus
```

## Example Queries

```sql
-- Today's dashboard facts (Dubai timezone)
SELECT * FROM life.daily_facts WHERE date = life.dubai_today();

-- Weekly health trends
SELECT date, recovery_score, sleep_score, hrv_avg, rhr_avg, weight_kg
FROM life.daily_facts
WHERE date >= life.dubai_today() - INTERVAL '7 days'
ORDER BY date DESC;

-- Today's finance summary
SELECT * FROM finance.v_timeline
WHERE date = life.dubai_today();

-- Search foods (2.4M rows, trigram search)
SELECT * FROM nutrition.search_foods('chicken breast', 10);
```

## Migration

See [MIGRATION.md](MIGRATION.md) for moving to a new machine.

Quick version:
```bash
# On old machine
./backup.sh
scp backups/nexus_backup_*.sql.gz newmachine:/tmp/

# On new machine
sudo ./setup.sh
sudo ./restore.sh /tmp/nexus_backup_*.sql.gz
```
