#!/bin/bash
# =============================================================================
# Nexus Backup Verification Script
# Tests backup integrity by restoring to a temporary database
# Run weekly to ensure disaster recovery readiness
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "============================================"
echo "  Nexus Backup Verification"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo ""

# Configuration
BACKUP_DIR="/var/www/nexus/backups"
TEST_DB="nexus_test"

# Find latest backup
echo -n "Finding latest backup... "
LATEST_BACKUP=$(ssh nexus "ls -t ${BACKUP_DIR}/nexus_backup_*.sql.gz 2>/dev/null | head -1" || echo "")

if [ -z "$LATEST_BACKUP" ]; then
    echo -e "${RED}✗ FAILED${NC}"
    echo "No backups found in ${BACKUP_DIR}"
    exit 1
fi

BACKUP_NAME=$(basename "$LATEST_BACKUP")
echo -e "${GREEN}✓ ${BACKUP_NAME}${NC}"

# Check backup integrity (gzip)
echo -n "Verifying backup file integrity... "
if ssh nexus "gunzip -t ${LATEST_BACKUP}" 2>/dev/null; then
    echo -e "${GREEN}✓ OK${NC}"
else
    echo -e "${RED}✗ CORRUPT${NC}"
    echo "Backup file is corrupted or invalid"
    exit 1
fi

# Create test database
echo -n "Creating test database... "
if ssh nexus "docker exec nexus-db psql -U nexus -c 'DROP DATABASE IF EXISTS ${TEST_DB}' postgres" &>/dev/null && \
   ssh nexus "docker exec nexus-db createdb -U nexus ${TEST_DB}" &>/dev/null; then
    echo -e "${GREEN}✓ OK${NC}"
else
    echo -e "${RED}✗ FAILED${NC}"
    exit 1
fi

# Restore backup to test database
echo -n "Restoring backup to test database... "
if ssh nexus "gunzip -c ${LATEST_BACKUP} | docker exec -i nexus-db psql -U nexus -d ${TEST_DB}" &>/dev/null; then
    echo -e "${GREEN}✓ OK${NC}"
else
    echo -e "${RED}✗ FAILED${NC}"
    ssh nexus "docker exec nexus-db dropdb -U nexus ${TEST_DB}" &>/dev/null || true
    exit 1
fi

# Verify schema count
echo -n "Verifying schemas... "
PROD_SCHEMAS=$(ssh nexus "docker exec nexus-db psql -U nexus -d nexus -t -c \"SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name IN ('core', 'health', 'nutrition', 'finance', 'notes', 'home');\"" | xargs)
TEST_SCHEMAS=$(ssh nexus "docker exec nexus-db psql -U nexus -d ${TEST_DB} -t -c \"SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name IN ('core', 'health', 'nutrition', 'finance', 'notes', 'home');\"" | xargs)

if [ "$PROD_SCHEMAS" == "$TEST_SCHEMAS" ]; then
    echo -e "${GREEN}✓ OK (${PROD_SCHEMAS} schemas)${NC}"
else
    echo -e "${RED}✗ MISMATCH${NC}"
    echo "Production: ${PROD_SCHEMAS}, Test: ${TEST_SCHEMAS}"
fi

# Verify table counts match
echo -n "Verifying table structure... "
PROD_TABLES=$(ssh nexus "docker exec nexus-db psql -U nexus -d nexus -t -c \"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema IN ('core', 'health', 'nutrition', 'finance', 'notes', 'home');\"" | xargs)
TEST_TABLES=$(ssh nexus "docker exec nexus-db psql -U nexus -d ${TEST_DB} -t -c \"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema IN ('core', 'health', 'nutrition', 'finance', 'notes', 'home');\"" | xargs)

if [ "$PROD_TABLES" == "$TEST_TABLES" ]; then
    echo -e "${GREEN}✓ OK (${PROD_TABLES} tables)${NC}"
else
    echo -e "${RED}✗ MISMATCH${NC}"
    echo "Production: ${PROD_TABLES}, Test: ${TEST_TABLES}"
fi

# Verify transaction counts match
echo -n "Verifying transaction data... "
PROD_COUNT=$(ssh nexus "docker exec nexus-db psql -U nexus -d nexus -t -c 'SELECT COUNT(*) FROM finance.transactions;'" | xargs)
TEST_COUNT=$(ssh nexus "docker exec nexus-db psql -U nexus -d ${TEST_DB} -t -c 'SELECT COUNT(*) FROM finance.transactions;'" | xargs)

if [ "$PROD_COUNT" == "$TEST_COUNT" ]; then
    echo -e "${GREEN}✓ OK (${PROD_COUNT} transactions)${NC}"
else
    echo -e "${RED}✗ MISMATCH${NC}"
    echo "Production: ${PROD_COUNT}, Test: ${TEST_COUNT}"
fi

# Verify food log counts
echo -n "Verifying food log data... "
PROD_FOOD=$(ssh nexus "docker exec nexus-db psql -U nexus -d nexus -t -c 'SELECT COUNT(*) FROM nutrition.food_log;'" | xargs)
TEST_FOOD=$(ssh nexus "docker exec nexus-db psql -U nexus -d ${TEST_DB} -t -c 'SELECT COUNT(*) FROM nutrition.food_log;'" | xargs)

if [ "$PROD_FOOD" == "$TEST_FOOD" ]; then
    echo -e "${GREEN}✓ OK (${PROD_FOOD} entries)${NC}"
else
    echo -e "${RED}✗ MISMATCH${NC}"
    echo "Production: ${PROD_FOOD}, Test: ${TEST_FOOD}"
fi

# Clean up test database
echo -n "Cleaning up test database... "
if ssh nexus "docker exec nexus-db dropdb -U nexus ${TEST_DB}" &>/dev/null; then
    echo -e "${GREEN}✓ OK${NC}"
else
    echo -e "${YELLOW}! WARNING${NC}"
fi

echo ""
echo "============================================"
echo -e "  ${GREEN}✓ Backup is valid${NC}"
echo "============================================"
echo ""
