#!/bin/bash
# =============================================================================
# Nexus Setup Script
# Personal Life Data Hub - PostgreSQL + NocoDB
# =============================================================================

set -euo pipefail

# Configuration
NEXUS_DIR="/var/www/nexus"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIN_DISK_GB=5
MIN_RAM_MB=1024

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Header
echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}    Nexus - Personal Life Data Hub${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# =============================================================================
# Pre-flight Checks
# =============================================================================

# Check for root/sudo
if [ "$EUID" -ne 0 ]; then
    log_error "Please run with sudo: sudo ./setup.sh"
    exit 1
fi
log_success "Running as root"

# Check architecture
ARCH=$(uname -m)
log_info "Architecture: ${ARCH}"

# Check disk space
AVAILABLE_GB=$(df -BG "${NEXUS_DIR%/*}" 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G' || echo "0")
if [ -z "$AVAILABLE_GB" ] || [ "$AVAILABLE_GB" -lt "$MIN_DISK_GB" ]; then
    AVAILABLE_GB=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
fi
if [ "$AVAILABLE_GB" -lt "$MIN_DISK_GB" ]; then
    log_error "Insufficient disk space. Need ${MIN_DISK_GB}GB, have ${AVAILABLE_GB}GB"
    exit 1
fi
log_success "Disk space: ${AVAILABLE_GB}GB available"

# Check RAM
TOTAL_RAM_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "2048")
if [ "$TOTAL_RAM_MB" -lt "$MIN_RAM_MB" ]; then
    log_warn "Low RAM: ${TOTAL_RAM_MB}MB (recommended: ${MIN_RAM_MB}MB+)"
else
    log_success "RAM: ${TOTAL_RAM_MB}MB available"
fi

# Check for existing installation
if [ -d "${NEXUS_DIR}" ] && [ -f "${NEXUS_DIR}/docker-compose.yml" ]; then
    echo ""
    log_warn "Existing Nexus installation found at ${NEXUS_DIR}"
    echo ""
    read -p "Options: [u]pgrade, [r]einstall (wipes data), [c]ancel: " -n 1 -r
    echo ""
    case $REPLY in
        [Uu])
            log_info "Upgrading existing installation..."
            UPGRADE_MODE=true
            ;;
        [Rr])
            log_warn "This will DELETE all existing data!"
            read -p "Type 'yes' to confirm: " -r
            if [ "$REPLY" != "yes" ]; then
                log_info "Cancelled."
                exit 0
            fi
            log_info "Removing existing installation..."
            cd "${NEXUS_DIR}" && docker compose down -v 2>/dev/null || true
            rm -rf "${NEXUS_DIR}"
            UPGRADE_MODE=false
            ;;
        *)
            log_info "Cancelled."
            exit 0
            ;;
    esac
else
    UPGRADE_MODE=false
fi

# =============================================================================
# Install Dependencies
# =============================================================================

echo ""
log_info "Checking dependencies..."

# Check for Docker
if ! command -v docker &> /dev/null; then
    log_info "Docker not found. Installing..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    log_success "Docker installed"
else
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
    log_success "Docker ${DOCKER_VERSION} found"
fi

# Check Docker is running
if ! docker info &> /dev/null; then
    log_info "Starting Docker..."
    systemctl start docker
    sleep 3
fi

# Check for Docker Compose
if ! docker compose version &> /dev/null; then
    log_info "Docker Compose not found. Installing..."
    apt-get update -qq && apt-get install -y -qq docker-compose-plugin
    log_success "Docker Compose installed"
else
    COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || echo "unknown")
    log_success "Docker Compose ${COMPOSE_VERSION} found"
fi

# =============================================================================
# Setup Directory Structure
# =============================================================================

echo ""
log_info "Setting up directory structure..."

mkdir -p "${NEXUS_DIR}"
mkdir -p "${NEXUS_DIR}/backups"

# Copy files
cp "${SCRIPT_DIR}/docker-compose.yml" "${NEXUS_DIR}/"
cp "${SCRIPT_DIR}/init.sql" "${NEXUS_DIR}/"
cp "${SCRIPT_DIR}/init-extended.sql" "${NEXUS_DIR}/" 2>/dev/null || true

# Copy scripts if they exist
for script in backup.sh restore.sh healthcheck.sh; do
    if [ -f "${SCRIPT_DIR}/${script}" ]; then
        cp "${SCRIPT_DIR}/${script}" "${NEXUS_DIR}/"
        chmod +x "${NEXUS_DIR}/${script}"
    fi
done

log_success "Files copied to ${NEXUS_DIR}"

# =============================================================================
# Generate Configuration
# =============================================================================

if [ ! -f "${NEXUS_DIR}/.env" ] || [ "$UPGRADE_MODE" = false ]; then
    echo ""
    log_info "Generating configuration..."

    # Generate secure passwords
    POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
    NC_JWT_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)

    # Detect timezone
    if [ -f /etc/timezone ]; then
        TZ=$(cat /etc/timezone)
    elif [ -L /etc/localtime ]; then
        TZ=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')
    else
        TZ="UTC"
    fi

    # Get IP for public URL
    LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")

    cat > "${NEXUS_DIR}/.env" << EOF
# =============================================================================
# Nexus Configuration
# Generated: $(date -Iseconds)
# =============================================================================

# PostgreSQL
POSTGRES_USER=nexus
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=nexus
POSTGRES_PORT=5432

# NocoDB
NOCODB_PORT=8080
NC_JWT_SECRET=${NC_JWT_SECRET}
NC_PUBLIC_URL=http://${LOCAL_IP}:8080

# Optional: pgAdmin (start with --profile admin)
PGADMIN_EMAIL=admin@nexus.local
PGADMIN_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
PGADMIN_PORT=5050

# System
TZ=${TZ}
EOF

    chmod 600 "${NEXUS_DIR}/.env"

    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}  CREDENTIALS (SAVE THESE!)${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    echo -e "  PostgreSQL Password: ${YELLOW}${POSTGRES_PASSWORD}${NC}"
    echo ""
    echo -e "  Stored in: ${NEXUS_DIR}/.env"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
else
    log_info "Using existing .env configuration"
fi

# Set ownership
chown -R root:root "${NEXUS_DIR}"

# =============================================================================
# Start Services
# =============================================================================

echo ""
log_info "Starting Nexus services..."

cd "${NEXUS_DIR}"

# Pull images first
docker compose pull -q

# Start services
docker compose up -d

# Wait for health checks
echo ""
log_info "Waiting for services to be healthy..."

TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    PG_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' nexus-db 2>/dev/null || echo "starting")
    if [ "$PG_HEALTH" = "healthy" ]; then
        break
    fi
    echo -n "."
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done
echo ""

if [ "$PG_HEALTH" = "healthy" ]; then
    log_success "PostgreSQL is healthy"
else
    log_warn "PostgreSQL health check timed out (may still be initializing)"
fi

# Check NocoDB
sleep 5
NC_HEALTH=$(docker inspect --format='{{.State.Status}}' nexus-ui 2>/dev/null || echo "unknown")
if [ "$NC_HEALTH" = "running" ]; then
    log_success "NocoDB is running"
else
    log_warn "NocoDB status: ${NC_HEALTH}"
fi

# =============================================================================
# Summary
# =============================================================================

LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
source "${NEXUS_DIR}/.env"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}    Nexus Setup Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Services:"
echo -e "  PostgreSQL:  ${BLUE}localhost:${POSTGRES_PORT:-5432}${NC}"
echo -e "  NocoDB UI:   ${BLUE}http://${LOCAL_IP}:${NOCODB_PORT:-8080}${NC}"
echo ""
echo "n8n Connection String:"
echo -e "  ${YELLOW}postgresql://nexus:PASSWORD@${LOCAL_IP}:${POSTGRES_PORT:-5432}/nexus${NC}"
echo ""
echo "Commands:"
echo "  View logs:      cd ${NEXUS_DIR} && docker compose logs -f"
echo "  Backup:         ${NEXUS_DIR}/backup.sh"
echo "  Restore:        ${NEXUS_DIR}/restore.sh <backup.sql.gz>"
echo "  Health check:   ${NEXUS_DIR}/healthcheck.sh"
echo "  Start pgAdmin:  cd ${NEXUS_DIR} && docker compose --profile admin up -d"
echo ""
echo "Next steps:"
echo "  1. Add 'nexus.rfanw' to Caddy reverse proxy"
echo "  2. Create PostgreSQL credential in n8n"
echo "  3. Build your first workflow!"
echo ""
