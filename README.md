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

```
nexus/
├── core/       → daily_summary, settings, tags
├── health/     → metrics, workouts, metric_types
├── nutrition/  → ingredients, meals, meal_ingredients, food_log, water_log
├── finance/    → accounts, transactions, grocery_items, merchant_rules, budgets
├── notes/      → entries (Obsidian metadata index)
└── home/       → device_snapshots, kitchen_events
```

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
-- Today's nutrition
SELECT * FROM nutrition.get_daily_totals(CURRENT_DATE);

-- Weekly health trends
SELECT date, weight_kg, recovery_score, calories_consumed, protein_g
FROM core.daily_summary
WHERE date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY date DESC;

-- Cost per gram of protein
SELECT item_name, total_price,
  ROUND((total_price / (protein_per_100g * quantity / 100))::numeric, 2) as cost_per_g_protein
FROM finance.grocery_items gi
JOIN nutrition.ingredients i ON gi.ingredient_id = i.id
WHERE protein_per_100g > 10
ORDER BY cost_per_g_protein;

-- Batch meals with portions remaining
SELECT name, portions_remaining, calories_per_portion, expiry_date
FROM nutrition.meals
WHERE portions_remaining > 0
ORDER BY expiry_date;
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
