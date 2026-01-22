#!/bin/bash
# =============================================================================
# Nexus Health Check Script
# Monitors database and services, outputs JSON for n8n integration
# =============================================================================

set -uo pipefail

# Configuration
NEXUS_DIR="/var/www/nexus"
OUTPUT_FORMAT="${1:-text}"  # text or json

# Colors (for text output)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load environment
if [ -f "${NEXUS_DIR}/.env" ]; then
    source "${NEXUS_DIR}/.env"
else
    POSTGRES_USER="nexus"
    POSTGRES_DB="nexus"
fi

# =============================================================================
# Health Checks
# =============================================================================

# Initialize status
OVERALL_STATUS="healthy"
CHECKS=()

# Check 1: PostgreSQL container
PG_CONTAINER=$(docker inspect --format='{{.State.Status}}' nexus-db 2>/dev/null || echo "not_found")
PG_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' nexus-db 2>/dev/null || echo "unknown")

if [ "$PG_CONTAINER" = "running" ] && [ "$PG_HEALTH" = "healthy" ]; then
    CHECKS+=("postgres:ok:Container running and healthy")
else
    CHECKS+=("postgres:error:Container ${PG_CONTAINER}, health ${PG_HEALTH}")
    OVERALL_STATUS="unhealthy"
fi

# Check 2: PostgreSQL connection
if docker exec nexus-db pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" &>/dev/null; then
    CHECKS+=("pg_connection:ok:Database accepting connections")
else
    CHECKS+=("pg_connection:error:Database not accepting connections")
    OVERALL_STATUS="unhealthy"
fi

# Check 3: NocoDB container
NC_CONTAINER=$(docker inspect --format='{{.State.Status}}' nexus-ui 2>/dev/null || echo "not_found")
NC_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' nexus-ui 2>/dev/null || echo "unknown")

if [ "$NC_CONTAINER" = "running" ]; then
    if [ "$NC_HEALTH" = "healthy" ] || [ "$NC_HEALTH" = "unknown" ]; then
        CHECKS+=("nocodb:ok:Container running")
    else
        CHECKS+=("nocodb:warning:Container running but health ${NC_HEALTH}")
        [ "$OVERALL_STATUS" = "healthy" ] && OVERALL_STATUS="degraded"
    fi
else
    CHECKS+=("nocodb:error:Container ${NC_CONTAINER}")
    [ "$OVERALL_STATUS" = "healthy" ] && OVERALL_STATUS="degraded"
fi

# Check 4: Database size
DB_SIZE_BYTES=$(docker exec nexus-db psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -c \
    "SELECT pg_database_size('${POSTGRES_DB}');" 2>/dev/null | xargs || echo "0")
DB_SIZE_PRETTY=$(docker exec nexus-db psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -c \
    "SELECT pg_size_pretty(pg_database_size('${POSTGRES_DB}'));" 2>/dev/null | xargs || echo "unknown")

# Warn if over 1GB
if [ "$DB_SIZE_BYTES" -gt 1073741824 ] 2>/dev/null; then
    CHECKS+=("db_size:warning:Database size ${DB_SIZE_PRETTY} (over 1GB)")
    [ "$OVERALL_STATUS" = "healthy" ] && OVERALL_STATUS="degraded"
else
    CHECKS+=("db_size:ok:${DB_SIZE_PRETTY}")
fi

# Check 5: Disk space for backups
BACKUP_DIR="${NEXUS_DIR}/backups"
if [ -d "$BACKUP_DIR" ]; then
    DISK_AVAIL=$(df -B1 "$BACKUP_DIR" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    DISK_AVAIL_GB=$((DISK_AVAIL / 1073741824))

    if [ "$DISK_AVAIL_GB" -lt 2 ]; then
        CHECKS+=("disk_space:warning:Only ${DISK_AVAIL_GB}GB available for backups")
        [ "$OVERALL_STATUS" = "healthy" ] && OVERALL_STATUS="degraded"
    else
        CHECKS+=("disk_space:ok:${DISK_AVAIL_GB}GB available")
    fi
else
    CHECKS+=("disk_space:warning:Backup directory not found")
fi

# Check 6: Recent backup
LATEST_BACKUP=$(ls -t "${BACKUP_DIR}"/nexus_backup_*.sql.gz 2>/dev/null | head -1)
if [ -n "$LATEST_BACKUP" ]; then
    BACKUP_AGE_HOURS=$(( ($(date +%s) - $(stat -c %Y "$LATEST_BACKUP" 2>/dev/null || stat -f %m "$LATEST_BACKUP" 2>/dev/null || echo 0)) / 3600 ))
    if [ "$BACKUP_AGE_HOURS" -gt 48 ]; then
        CHECKS+=("backup_age:warning:Last backup ${BACKUP_AGE_HOURS}h ago")
        [ "$OVERALL_STATUS" = "healthy" ] && OVERALL_STATUS="degraded"
    else
        CHECKS+=("backup_age:ok:Last backup ${BACKUP_AGE_HOURS}h ago")
    fi
else
    CHECKS+=("backup_age:warning:No backups found")
    [ "$OVERALL_STATUS" = "healthy" ] && OVERALL_STATUS="degraded"
fi

# Check 7: Schema verification
SCHEMA_COUNT=$(docker exec nexus-db psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -c \
    "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name IN ('core', 'health', 'nutrition', 'finance', 'notes', 'home');" 2>/dev/null | xargs || echo "0")

if [ "$SCHEMA_COUNT" -eq 6 ]; then
    CHECKS+=("schemas:ok:All 6 schemas present")
else
    CHECKS+=("schemas:error:Only ${SCHEMA_COUNT}/6 schemas found")
    OVERALL_STATUS="unhealthy"
fi

# Check 8: Table count
TABLE_COUNT=$(docker exec nexus-db psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -c \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema IN ('core', 'health', 'nutrition', 'finance', 'notes', 'home');" 2>/dev/null | xargs || echo "0")
CHECKS+=("tables:ok:${TABLE_COUNT} tables")

# Check 9: Daily summary freshness (if data exists)
LATEST_SUMMARY=$(docker exec nexus-db psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -c \
    "SELECT MAX(date)::text FROM core.daily_summary;" 2>/dev/null | xargs || echo "")

if [ -n "$LATEST_SUMMARY" ] && [ "$LATEST_SUMMARY" != "" ]; then
    DAYS_OLD=$(( ($(date +%s) - $(date -d "$LATEST_SUMMARY" +%s 2>/dev/null || echo $(date +%s))) / 86400 ))
    if [ "$DAYS_OLD" -gt 2 ]; then
        CHECKS+=("data_freshness:warning:Latest data from ${LATEST_SUMMARY} (${DAYS_OLD} days old)")
    else
        CHECKS+=("data_freshness:ok:Latest data from ${LATEST_SUMMARY}")
    fi
else
    CHECKS+=("data_freshness:info:No data logged yet")
fi

# =============================================================================
# Output
# =============================================================================

if [ "$OUTPUT_FORMAT" = "json" ]; then
    # JSON output for n8n
    echo "{"
    echo "  \"status\": \"${OVERALL_STATUS}\","
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"database_size\": \"${DB_SIZE_PRETTY}\","
    echo "  \"table_count\": ${TABLE_COUNT},"
    echo "  \"checks\": ["

    FIRST=true
    for check in "${CHECKS[@]}"; do
        IFS=':' read -r name status message <<< "$check"
        [ "$FIRST" = false ] && echo ","
        echo -n "    {\"name\": \"${name}\", \"status\": \"${status}\", \"message\": \"${message}\"}"
        FIRST=false
    done

    echo ""
    echo "  ]"
    echo "}"
else
    # Text output for humans
    echo ""
    echo "============================================"
    echo "  Nexus Health Check"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================"
    echo ""

    for check in "${CHECKS[@]}"; do
        IFS=':' read -r name status message <<< "$check"
        case $status in
            ok)      echo -e "  ${GREEN}✓${NC} ${name}: ${message}" ;;
            warning) echo -e "  ${YELLOW}!${NC} ${name}: ${message}" ;;
            error)   echo -e "  ${RED}✗${NC} ${name}: ${message}" ;;
            info)    echo -e "  ${BLUE}i${NC} ${name}: ${message}" ;;
        esac
    done

    echo ""
    echo "============================================"
    case $OVERALL_STATUS in
        healthy)  echo -e "  Overall: ${GREEN}HEALTHY${NC}" ;;
        degraded) echo -e "  Overall: ${YELLOW}DEGRADED${NC}" ;;
        unhealthy) echo -e "  Overall: ${RED}UNHEALTHY${NC}" ;;
    esac
    echo "============================================"
    echo ""
fi

# Exit code based on status
case $OVERALL_STATUS in
    healthy)   exit 0 ;;
    degraded)  exit 1 ;;
    unhealthy) exit 2 ;;
esac
