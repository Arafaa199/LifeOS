#!/bin/bash
# =============================================================================
# Nexus Remote Health Check
# Simple monitoring script that runs from local machine to check remote server
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "============================================"
echo "  Nexus Remote Health Check"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo ""

# Check 1: Database
echo -n "Checking database... "
if ssh nexus "docker exec nexus-db pg_isready" &>/dev/null; then
    echo -e "${GREEN}✓ OK${NC}"
else
    echo -e "${RED}✗ DB DOWN${NC}"
fi

# Check 2: n8n
echo -n "Checking n8n... "
if curl -sf https://n8n.rfanw/healthz &>/dev/null; then
    echo -e "${GREEN}✓ OK${NC}"
else
    echo -e "${RED}✗ n8n DOWN${NC}"
fi

# Check 3: Disk space
echo -n "Checking disk space... "
DISK_FULL=$(ssh nexus "df -h | grep -E '9[0-9]%|100%'" || true)
if [ -n "$DISK_FULL" ]; then
    echo -e "${YELLOW}⚠️  DISK FULL${NC}"
    echo "$DISK_FULL"
else
    echo -e "${GREEN}✓ OK${NC}"
fi

# Check 4: Docker containers
echo -n "Checking containers... "
CONTAINERS=$(ssh nexus "docker ps --filter 'name=nexus' --format '{{.Names}}: {{.Status}}'" || echo "")
if [ -n "$CONTAINERS" ]; then
    echo -e "${GREEN}✓ OK${NC}"
    echo "$CONTAINERS" | sed 's/^/  /'
else
    echo -e "${RED}✗ NO CONTAINERS${NC}"
fi

echo ""
echo "============================================"
