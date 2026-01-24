#!/bin/bash
# Receipt Ingestion Service - Server Installation Script
# Run on nexus server as root

set -e

INSTALL_DIR="/opt/lifeos/receipt-ingest"
SECRETS_DIR="/opt/lifeos/secrets"
DATA_DIR="/opt/lifeos/data/receipts"
LOG_DIR="/opt/lifeos/logs"

echo "=== Installing LifeOS Receipt Ingestion Service ==="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
fi

# Create directories
echo "Creating directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$SECRETS_DIR"
mkdir -p "$DATA_DIR"
mkdir -p "$LOG_DIR"

# Set permissions
chown -R scrypt:scrypt /opt/lifeos
chmod 700 "$SECRETS_DIR"
chmod 755 "$DATA_DIR"
chmod 755 "$LOG_DIR"

# Copy application files
echo "Copying application files..."
cp Dockerfile "$INSTALL_DIR/"
cp docker-compose.yml "$INSTALL_DIR/"
cp requirements.txt "$INSTALL_DIR/"
cp entrypoint.sh "$INSTALL_DIR/"
cp carrefour_parser.py "$INSTALL_DIR/"
cp receipt_ingestion.py "$INSTALL_DIR/"

# Install systemd units
echo "Installing systemd units..."
cp lifeos-receipt-ingest.service /etc/systemd/system/
cp lifeos-receipt-ingest.timer /etc/systemd/system/

# Reload systemd
systemctl daemon-reload

# Check for secrets
echo ""
echo "=== Secrets Setup ==="
if [ ! -f "$SECRETS_DIR/gmail_client_secret.json" ]; then
    echo "WARNING: Gmail client secret not found!"
    echo "Copy gmail_client_secret.json to $SECRETS_DIR/"
fi

if [ ! -f "$SECRETS_DIR/token.pickle" ]; then
    echo "WARNING: Gmail token not found!"
    echo "Copy token.pickle to $SECRETS_DIR/"
fi

if [ ! -f "$SECRETS_DIR/receipt-ingest.env" ]; then
    echo "Creating environment file..."
    echo "NEXUS_PASSWORD=" > "$SECRETS_DIR/receipt-ingest.env"
    chmod 600 "$SECRETS_DIR/receipt-ingest.env"
    echo "WARNING: Set NEXUS_PASSWORD in $SECRETS_DIR/receipt-ingest.env"
fi

# Build Docker image
echo ""
echo "=== Building Docker Image ==="
cd "$INSTALL_DIR"
docker compose build

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next steps:"
echo "1. Copy secrets to $SECRETS_DIR/:"
echo "   - gmail_client_secret.json"
echo "   - token.pickle"
echo ""
echo "2. Set database password:"
echo "   echo 'NEXUS_PASSWORD=your-password' > $SECRETS_DIR/receipt-ingest.env"
echo ""
echo "3. Test the service:"
echo "   systemctl start lifeos-receipt-ingest"
echo "   journalctl -u lifeos-receipt-ingest -f"
echo ""
echo "4. Enable the timer:"
echo "   systemctl enable --now lifeos-receipt-ingest.timer"
echo "   systemctl list-timers | grep receipt"
echo ""
echo "5. Manual run options:"
echo "   cd $INSTALL_DIR"
echo "   docker compose run --rm receipt-ingest --fetch"
echo "   docker compose run --rm receipt-ingest --parse"
echo "   docker compose run --rm receipt-ingest --link"
