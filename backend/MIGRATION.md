# Nexus Migration Guide

Moving Nexus from one machine to another is straightforward.

## Quick Migration (5 commands)

### On OLD machine (pivpn):
```bash
# 1. Create backup
cd /var/www/nexus
./backup.sh

# 2. Copy backup to new machine
scp backups/nexus_backup_*.sql.gz user@new-machine:/tmp/
```

### On NEW machine:
```bash
# 3. Run setup (creates fresh Nexus)
sudo ./setup.sh

# 4. Find your backup file
BACKUP_FILE=$(ls -t /tmp/nexus_backup_*.sql.gz | head -1)

# 5. Restore data
gunzip -c $BACKUP_FILE | docker exec -i nexus-db psql -U nexus nexus
```

Done. Your new machine now has all your data.

---

## Detailed Steps

### Step 1: Backup on Old Machine

SSH into your pivpn:
```bash
ssh pivpn
cd /var/www/nexus
sudo ./backup.sh
```

This creates: `/var/www/nexus/backups/nexus_backup_YYYYMMDD_HHMMSS.sql.gz`

### Step 2: Copy Files to New Machine

Option A - Direct SCP:
```bash
# From old machine
scp /var/www/nexus/backups/nexus_backup_*.sql.gz user@newmachine:/tmp/
scp -r /var/www/nexus/*.yml /var/www/nexus/*.sql user@newmachine:/tmp/nexus-setup/
```

Option B - Through your local machine:
```bash
# Download from old
scp pivpn:/var/www/nexus/backups/nexus_backup_*.sql.gz ~/Downloads/

# Upload to new
scp ~/Downloads/nexus_backup_*.sql.gz newmachine:/tmp/
```

### Step 3: Setup on New Machine

```bash
ssh newmachine

# Copy the nexus-setup folder (or clone/download fresh)
cd /tmp/nexus-setup
sudo ./setup.sh
```

### Step 4: Restore Database

```bash
# Stop the database briefly to avoid conflicts
cd /var/www/nexus
docker compose stop nocodb  # Stop UI while restoring

# Drop existing (init) data and restore backup
BACKUP_FILE="/tmp/nexus_backup_YYYYMMDD_HHMMSS.sql.gz"
docker exec -i nexus-db psql -U nexus -c "DROP SCHEMA IF EXISTS core, health, nutrition, finance, notes, home CASCADE;"
gunzip -c $BACKUP_FILE | docker exec -i nexus-db psql -U nexus nexus

# Restart everything
docker compose up -d
```

### Step 5: Update n8n Connection

In your n8n instance, update the PostgreSQL credentials:
- Host: new machine IP
- Port: 5432
- Database: nexus
- User: nexus
- Password: (from new machine's /var/www/nexus/.env)

---

## Volume Migration (Alternative)

If you prefer to migrate the raw Docker volume:

```bash
# On old machine - export volume
docker run --rm -v nexus_postgres_data:/data -v $(pwd):/backup alpine tar czf /backup/postgres_volume.tar.gz /data

# Copy to new machine
scp postgres_volume.tar.gz newmachine:/tmp/

# On new machine - import volume
docker compose down
docker volume rm nexus_postgres_data 2>/dev/null || true
docker volume create nexus_postgres_data
docker run --rm -v nexus_postgres_data:/data -v /tmp:/backup alpine tar xzf /backup/postgres_volume.tar.gz -C /
docker compose up -d
```

---

## Checklist

- [ ] Backup created on old machine
- [ ] Backup file transferred to new machine
- [ ] New machine has Docker installed
- [ ] Setup script ran successfully
- [ ] Database restored from backup
- [ ] n8n connection updated
- [ ] NocoDB accessible on new machine
- [ ] Old machine decommissioned (optional)

---

## Rollback

If something goes wrong on the new machine:

```bash
cd /var/www/nexus
docker compose down -v  # Remove everything including volumes
sudo ./setup.sh         # Fresh start
# Then restore from backup again
```

Your backup file is the source of truth. Keep it safe.
