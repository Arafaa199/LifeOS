#!/bin/bash
# =============================================================================
# Nexus Backup Script
# Creates timestamped backups with optional remote sync and notifications
# =============================================================================

set -euo pipefail

# Configuration
NEXUS_DIR="/var/www/nexus"
BACKUP_DIR="${NEXUS_DIR}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/nexus_backup_${TIMESTAMP}.sql.gz"
RETENTION_COUNT=7

# Remote backup config (optional - set in .env or here)
REMOTE_ENABLED=${REMOTE_BACKUP_ENABLED:-false}
REMOTE_HOST=${REMOTE_BACKUP_HOST:-"nas"}
REMOTE_PATH=${REMOTE_BACKUP_PATH:-"/Volume2/Backups/nexus"}
REMOTE_USER=${REMOTE_BACKUP_USER:-"rafa"}

# Notification config (optional - uses pivpn email service)
NOTIFY_ENABLED=${BACKUP_NOTIFY_ENABLED:-false}
NOTIFY_URL=${BACKUP_NOTIFY_URL:-"http://172.17.0.1:8025/send-email"}
NOTIFY_EMAIL=${BACKUP_NOTIFY_EMAIL:-""}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging
log_info() { echo -e "[$(date '+%H:%M:%S')] ${GREEN}INFO${NC} $1"; }
log_warn() { echo -e "[$(date '+%H:%M:%S')] ${YELLOW}WARN${NC} $1"; }
log_error() { echo -e "[$(date '+%H:%M:%S')] ${RED}ERROR${NC} $1"; }

# Send notification
send_notification() {
    local subject="$1"
    local body="$2"
    local status="$3"  # success or failure

    if [ "$NOTIFY_ENABLED" = "true" ] && [ -n "$NOTIFY_EMAIL" ]; then
        curl -s -X POST "$NOTIFY_URL" \
            -H "Content-Type: application/json" \
            -d "{\"to\": \"${NOTIFY_EMAIL}\", \"subject\": \"[Nexus] ${subject}\", \"body\": \"${body}\"}" \
            > /dev/null 2>&1 || true
    fi
}

# Cleanup on error
cleanup() {
    if [ -f "${BACKUP_FILE}" ] && [ ! -s "${BACKUP_FILE}" ]; then
        rm -f "${BACKUP_FILE}"
    fi
}
trap cleanup ERR

# =============================================================================
# Main
# =============================================================================

echo ""
echo "============================================"
echo "  Nexus Database Backup"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo ""

# Load environment
if [ -f "${NEXUS_DIR}/.env" ]; then
    source "${NEXUS_DIR}/.env"
else
    log_error ".env file not found at ${NEXUS_DIR}/.env"
    exit 1
fi

# Create backup directory if needed
mkdir -p "${BACKUP_DIR}"

# Check if database is running
if ! docker ps --format '{{.Names}}' | grep -q '^nexus-db$'; then
    log_error "nexus-db container is not running"
    send_notification "Backup Failed" "Database container not running" "failure"
    exit 1
fi

# Get database size for reference
DB_SIZE=$(docker exec nexus-db psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -c \
    "SELECT pg_size_pretty(pg_database_size('${POSTGRES_DB}'));" 2>/dev/null | xargs || echo "unknown")
log_info "Database size: ${DB_SIZE}"

# Create backup
log_info "Creating backup: ${BACKUP_FILE}"

START_TIME=$(date +%s)
docker exec nexus-db pg_dump -U "${POSTGRES_USER}" "${POSTGRES_DB}" 2>/dev/null | gzip > "${BACKUP_FILE}"
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Verify backup
if [ ! -f "${BACKUP_FILE}" ] || [ ! -s "${BACKUP_FILE}" ]; then
    log_error "Backup file is empty or missing"
    send_notification "Backup Failed" "Backup file creation failed" "failure"
    exit 1
fi

BACKUP_SIZE=$(ls -lh "${BACKUP_FILE}" | awk '{print $5}')
log_info "Backup size: ${BACKUP_SIZE} (completed in ${DURATION}s)"

# Integrity check - verify gzip
if ! gzip -t "${BACKUP_FILE}" 2>/dev/null; then
    log_error "Backup file integrity check failed"
    send_notification "Backup Failed" "Backup integrity check failed" "failure"
    exit 1
fi
log_info "Integrity check passed"

# Quick content check - ensure SQL structure exists
TABLES_COUNT=$(gunzip -c "${BACKUP_FILE}" | grep -c "CREATE TABLE" || echo "0")
if [ "$TABLES_COUNT" -lt 5 ]; then
    log_warn "Backup may be incomplete (only ${TABLES_COUNT} tables found)"
fi

# =============================================================================
# Remote Sync (optional)
# =============================================================================

if [ "$REMOTE_ENABLED" = "true" ]; then
    log_info "Syncing to remote: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"

    # Ensure remote directory exists
    ssh -o ConnectTimeout=10 "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p ${REMOTE_PATH}" 2>/dev/null || {
        log_warn "Could not create remote directory (may already exist)"
    }

    # Copy backup
    if scp -o ConnectTimeout=10 "${BACKUP_FILE}" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/" 2>/dev/null; then
        log_info "Remote sync complete"

        # Clean old remote backups (keep same retention)
        ssh "${REMOTE_USER}@${REMOTE_HOST}" \
            "ls -t ${REMOTE_PATH}/nexus_backup_*.sql.gz 2>/dev/null | tail -n +$((RETENTION_COUNT + 1)) | xargs -r rm" \
            2>/dev/null || true
    else
        log_warn "Remote sync failed (backup still saved locally)"
    fi
fi

# =============================================================================
# Cleanup Old Backups
# =============================================================================

log_info "Cleaning old backups (keeping last ${RETENTION_COUNT})..."
OLD_COUNT=$(ls -t "${BACKUP_DIR}"/nexus_backup_*.sql.gz 2>/dev/null | tail -n +$((RETENTION_COUNT + 1)) | wc -l || echo "0")
ls -t "${BACKUP_DIR}"/nexus_backup_*.sql.gz 2>/dev/null | tail -n +$((RETENTION_COUNT + 1)) | xargs -r rm 2>/dev/null || true

if [ "$OLD_COUNT" -gt 0 ]; then
    log_info "Removed ${OLD_COUNT} old backup(s)"
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "============================================"
echo "  Backup Complete"
echo "============================================"
echo ""
echo "  File:     ${BACKUP_FILE}"
echo "  Size:     ${BACKUP_SIZE}"
echo "  DB Size:  ${DB_SIZE}"
echo "  Duration: ${DURATION}s"
echo "  Tables:   ${TABLES_COUNT}"
if [ "$REMOTE_ENABLED" = "true" ]; then
    echo "  Remote:   ${REMOTE_HOST}:${REMOTE_PATH}"
fi
echo ""
echo "  Restore command:"
echo "    ./restore.sh ${BACKUP_FILE}"
echo ""

# Send success notification
send_notification "Backup Successful" "Size: ${BACKUP_SIZE}, Duration: ${DURATION}s, Tables: ${TABLES_COUNT}" "success"

exit 0
