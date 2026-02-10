#!/bin/bash
# Deploy API authentication to n8n workflows
# Run from: $NEXUS_SCRIPTS_DIR

set -e

NEXUS_API_KEY="${NEXUS_API_KEY:-}"
if [ -z "$NEXUS_API_KEY" ]; then
  echo "Error: NEXUS_API_KEY environment variable not set"
  exit 1
fi

echo "=== Nexus API Auth Deployment ==="
echo ""

# Step 1: Add env var to n8n container
echo "[1/4] Adding NEXUS_API_KEY to n8n container..."
echo ""
echo "  Run these commands on pivpn:"
echo ""
echo "  # Stop current container"
echo "  docker stop n8n"
echo ""
echo "  # Remove old container (data is persisted in volume)"
echo "  docker rm n8n"
echo ""
echo "  # Start with API key env var"
echo "  docker run -d --name n8n --restart=always \\"
echo "    -p 5678:5678 \\"
echo "    -e NEXUS_API_KEY=${NEXUS_API_KEY} \\"
echo "    -v \${N8N_DATA_DIR}:/home/node/.n8n \\"
echo "    docker.n8n.io/n8nio/n8n"
echo ""

# Step 2: Copy workflows to pivpn
echo "[2/4] Copying authenticated workflows to pivpn..."
echo ""
echo "  scp -r with-auth/*.json pivpn:~/nexus-workflows/"
echo ""

# Step 3: Import workflows in n8n UI
echo "[3/4] Import workflows in n8n UI"
echo ""
echo "  1. Open https://n8n.rfanw"
echo "  2. For each workflow in ~/nexus-workflows/:"
echo "     - Click the workflow name in sidebar"
echo "     - Click '...' menu → 'Import from File'"
echo "     - Select the matching file from with-auth/"
echo "     - Toggle workflow OFF then ON to re-register webhook"
echo ""

# Step 4: Test
echo "[4/4] Test authentication"
echo ""
echo "  # Should return 401 Unauthorized"
echo "  curl -s https://n8n.rfanw/webhook/nexus-finance-summary | jq"
echo ""
echo "  # Should return data"
echo "  curl -s -H 'X-API-Key: ${NEXUS_API_KEY}' https://n8n.rfanw/webhook/nexus-finance-summary | jq"
echo ""

# Step 5: iOS app
echo "[5/5] Configure iOS app"
echo ""
echo "  In Nexus app Settings, set API Key to:"
echo "  ${NEXUS_API_KEY}"
echo ""
echo "=== Done ==="
