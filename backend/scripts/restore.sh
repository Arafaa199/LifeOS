#!/bin/bash
# =============================================================================
# Nexus Restore Script
# Restores database from a backup file
# =============================================================================

set -euo pipefail

# Configuration
NEXUS_DIR="/var/www/nexus"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "[$(date '+%H:%M:%S')] ${BLUE}INFO${NC} $1"; }
log_success() { echo -e "[$(date '+%H:%M:%S')] ${GREEN}OK${NC} $1"; }
log_warn() { echo -e "[$(date '+%H:%M:%S')] ${YELLOW}WARN${NC} $1"; }
log_error() { echo -e "[$(date '+%H:%M:%S')] ${RED}ERROR${NC} $1"; }

# =============================================================================
# Usage
# =============================================================================

usage() {
    echo ""
    echo "Usage: $0 <backup_file.sql.gz>"
    echo ""
    echo "Options:"
    echo "  -f, --force     Skip confirmation prompt"
    echo "  -h, --help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 /var/www/nexus/backups/nexus_backup_20260119_030000.sql.gz"
    echo "  $0 -f nexus_backup_latest.sql.gz"
    echo ""
    exit 1
}

# =============================================================================
# Parse Arguments
# =============================================================================

FORCE=false
BACKUP_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            BACKUP_FILE="$1"
            shift
            ;;
    esac
done

if [ -z "$BACKUP_FILE" ]; then
    log_error "No backup file specified"
    usage
fi

# =============================================================================
# Validation
# =============================================================================

echo ""
echo "============================================"
echo "  Nexus Database Restore"
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

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    # Try with backup directory prefix
    if [ -f "${NEXUS_DIR}/backups/${BACKUP_FILE}" ]; then
        BACKUP_FILE="${NEXUS_DIR}/backups/${BACKUP_FILE}"
    else
        log_error "Backup file not found: ${BACKUP_FILE}"
        exit 1
    fi
fi

log_info "Backup file: ${BACKUP_FILE}"

# Check file extension
if [[ ! "$BACKUP_FILE" =~ \.sql\.gz$ ]] && [[ ! "$BACKUP_FILE" =~ \.sql$ ]]; then
    log_error "Invalid file format. Expected .sql.gz or .sql"
    exit 1
fi

# Verify gzip integrity if compressed
if [[ "$BACKUP_FILE" =~ \.gz$ ]]; then
    log_info "Verifying backup integrity..."
    if ! gzip -t "$BACKUP_FILE" 2>/dev/null; then
        log_error "Backup file is corrupted"
        exit 1
    fi
    log_success "Integrity check passed"

    # Get stats
    COMPRESSED_SIZE=$(ls -lh "$BACKUP_FILE" | awk '{print $5}')
    TABLES_COUNT=$(gunzip -c "$BACKUP_FILE" | grep -c "CREATE TABLE" || echo "0")
else
    COMPRESSED_SIZE=$(ls -lh "$BACKUP_FILE" | awk '{print $5}')
    TABLES_COUNT=$(grep -c "CREATE TABLE" "$BACKUP_FILE" || echo "0")
fi

log_info "Backup size: ${COMPRESSED_SIZE}"
log_info "Tables in backup: ${TABLES_COUNT}"

# Check if database is running
if ! docker ps --format '{{.Names}}' | grep -q '^nexus-db$'; then
    log_error "nexus-db container is not running"
    log_info "Start it with: cd ${NEXUS_DIR} && docker compose up -d"
    exit 1
fi

# Get current database stats
CURRENT_SIZE=$(docker exec nexus-db psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -c \
    "SELECT pg_size_pretty(pg_database_size('${POSTGRES_DB}'));" 2>/dev/null | xargs || echo "unknown")
log_info "Current database size: ${CURRENT_SIZE}"

# =============================================================================
# Confirmation
# =============================================================================

if [ "$FORCE" = false ]; then
    echo ""
    echo -e "${YELLOW}WARNING: This will replace ALL existing data!${NC}"
    echo ""
    echo "  Backup file:    ${BACKUP_FILE}"
    echo "  Backup size:    ${COMPRESSED_SIZE}"
    echo "  Tables:         ${TABLES_COUNT}"
    echo "  Current DB:     ${CURRENT_SIZE}"
    echo ""
    read -p "Type 'yes' to confirm restore: " -r
    echo ""
    if [ "$REPLY" != "yes" ]; then
        log_info "Restore cancelled"
        exit 0
    fi
fi

# =============================================================================
# Create Pre-Restore Backup
# =============================================================================

log_info "Creating pre-restore backup (just in case)..."
PRE_RESTORE_BACKUP="${NEXUS_DIR}/backups/pre_restore_$(date +%Y%m%d_%H%M%S).sql.gz"
docker exec nexus-db pg_dump -U "${POSTGRES_USER}" "${POSTGRES_DB}" 2>/dev/null | gzip > "$PRE_RESTORE_BACKUP" || {
    log_warn "Could not create pre-restore backup (continuing anyway)"
}
if [ -f "$PRE_RESTORE_BACKUP" ] && [ -s "$PRE_RESTORE_BACKUP" ]; then
    log_success "Pre-restore backup: ${PRE_RESTORE_BACKUP}"
fi

# =============================================================================
# Restore
# =============================================================================

log_info "Stopping dependent services..."
docker stop nexus-ui 2>/dev/null || true

log_info "Dropping existing schemas..."
docker exec nexus-db psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c \
    "DROP SCHEMA IF EXISTS core, health, nutrition, finance, notes, home CASCADE;" 2>/dev/null || true

log_info "Restoring database..."
START_TIME=$(date +%s)

if [[ "$BACKUP_FILE" =~ \.gz$ ]]; then
    gunzip -c "$BACKUP_FILE" | docker exec -i nexus-db psql -U "${POSTGRES_USER}" "${POSTGRES_DB}" 2>/dev/null
else
    docker exec -i nexus-db psql -U "${POSTGRES_USER}" "${POSTGRES_DB}" < "$BACKUP_FILE" 2>/dev/null
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# =============================================================================
# Verification
# =============================================================================

log_info "Verifying restore..."

# Check schemas exist
SCHEMAS=$(docker exec nexus-db psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -c \
    "SELECT string_agg(schema_name, ', ') FROM information_schema.schemata WHERE schema_name IN ('core', 'health', 'nutrition', 'finance', 'notes', 'home');" 2>/dev/null | xargs)

if [ -z "$SCHEMAS" ]; then
    log_error "Restore may have failed - no expected schemas found"
    log_info "You can restore from pre-restore backup: ${PRE_RESTORE_BACKUP}"
    exit 1
fi

log_success "Schemas restored: ${SCHEMAS}"

# Check table count
RESTORED_TABLES=$(docker exec nexus-db psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -c \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema IN ('core', 'health', 'nutrition', 'finance', 'notes', 'home');" 2>/dev/null | xargs)
log_success "Tables restored: ${RESTORED_TABLES}"

# Get new size
NEW_SIZE=$(docker exec nexus-db psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -c \
    "SELECT pg_size_pretty(pg_database_size('${POSTGRES_DB}'));" 2>/dev/null | xargs || echo "unknown")

# =============================================================================
# Restart Services
# =============================================================================

log_info "Restarting services..."
docker start nexus-ui 2>/dev/null || true

# Wait for NocoDB to be ready
sleep 5

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "============================================"
echo -e "  ${GREEN}Restore Complete${NC}"
echo "============================================"
echo ""
echo "  Source:         ${BACKUP_FILE}"
echo "  Duration:       ${DURATION}s"
echo "  Schemas:        ${SCHEMAS}"
echo "  Tables:         ${RESTORED_TABLES}"
echo "  Database size:  ${NEW_SIZE}"
echo ""
echo "  Pre-restore backup saved to:"
echo "    ${PRE_RESTORE_BACKUP}"
echo ""

log_success "Database restored successfully!"
