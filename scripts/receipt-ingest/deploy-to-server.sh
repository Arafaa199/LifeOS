#!/bin/bash
# Deploy Receipt Ingestion to Nexus Server
# Run from Mac: ./deploy-to-server.sh

set -e

SERVER="nexus"  # Uses SSH config
REMOTE_DIR="/tmp/receipt-ingest-deploy"
INSTALL_DIR="/opt/lifeos/receipt-ingest"
SECRETS_DIR="/opt/lifeos/secrets"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Deploying Receipt Ingestion to $SERVER ==="

# Create remote temp directory
echo "Creating remote temp directory..."
ssh "$SERVER" "mkdir -p $REMOTE_DIR"

# Copy all required files
echo "Copying files..."
scp "$SCRIPT_DIR/carrefour_parser.py" "$SERVER:$REMOTE_DIR/"
scp "$SCRIPT_DIR/receipt_ingestion.py" "$SERVER:$REMOTE_DIR/"
scp "$SCRIPT_DIR/deploy/Dockerfile" "$SERVER:$REMOTE_DIR/"
scp "$SCRIPT_DIR/deploy/docker-compose.yml" "$SERVER:$REMOTE_DIR/"
scp "$SCRIPT_DIR/deploy/requirements.txt" "$SERVER:$REMOTE_DIR/"
scp "$SCRIPT_DIR/deploy/entrypoint.sh" "$SERVER:$REMOTE_DIR/"
scp "$SCRIPT_DIR/deploy/lifeos-receipt-ingest.service" "$SERVER:$REMOTE_DIR/"
scp "$SCRIPT_DIR/deploy/lifeos-receipt-ingest.timer" "$SERVER:$REMOTE_DIR/"
scp "$SCRIPT_DIR/deploy/install.sh" "$SERVER:$REMOTE_DIR/"

# Copy secrets if they exist locally
if [ -f "$SCRIPT_DIR/gmail_client_secret.json" ]; then
    echo "Copying Gmail client secret..."
    scp "$SCRIPT_DIR/gmail_client_secret.json" "$SERVER:$REMOTE_DIR/"
fi

if [ -f "$SCRIPT_DIR/token.pickle" ]; then
    echo "Copying Gmail token..."
    scp "$SCRIPT_DIR/token.pickle" "$SERVER:$REMOTE_DIR/"
fi

# Run installation on server
echo ""
echo "=== Running installation on server ==="
ssh -t "$SERVER" "cd $REMOTE_DIR && sudo bash install.sh"

# Copy secrets to final location
echo ""
echo "=== Copying secrets ==="
if [ -f "$SCRIPT_DIR/gmail_client_secret.json" ]; then
    ssh "$SERVER" "sudo cp $REMOTE_DIR/gmail_client_secret.json $SECRETS_DIR/ && sudo chmod 600 $SECRETS_DIR/gmail_client_secret.json"
fi

if [ -f "$SCRIPT_DIR/token.pickle" ]; then
    ssh "$SERVER" "sudo cp $REMOTE_DIR/token.pickle $SECRETS_DIR/ && sudo chmod 600 $SECRETS_DIR/token.pickle"
fi

# Set database password
echo ""
echo "=== Setting database password ==="
source ~/Cyber/Infrastructure/Nexus-setup/.env
ssh "$SERVER" "echo 'NEXUS_PASSWORD=$NEXUS_PASSWORD' | sudo tee $SECRETS_DIR/receipt-ingest.env > /dev/null && sudo chmod 600 $SECRETS_DIR/receipt-ingest.env"

# Cleanup
echo ""
echo "Cleaning up temp files..."
ssh "$SERVER" "rm -rf $REMOTE_DIR"

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "To test:"
echo "  ssh $SERVER 'sudo systemctl start lifeos-receipt-ingest'"
echo "  ssh $SERVER 'sudo journalctl -u lifeos-receipt-ingest -f'"
echo ""
echo "To enable hourly timer:"
echo "  ssh $SERVER 'sudo systemctl enable --now lifeos-receipt-ingest.timer'"
