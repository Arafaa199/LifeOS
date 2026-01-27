#!/bin/bash
# Receipt Ingestion Runner
# Runs the full ingestion pipeline: fetch → parse → link

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
export SECRETS_DIR="$SCRIPT_DIR/secrets"
export PDF_STORAGE_PATH="/tmp/receipts"
export NEXUS_HOST="10.0.0.11"
export NEXUS_PORT="5432"
export NEXUS_DB="nexus"
export NEXUS_USER="nexus"

# Load password from secure location
if [[ -f "$HOME/.nexus-password" ]]; then
    export NEXUS_PASSWORD="$(cat "$HOME/.nexus-password")"
fi

# Ensure PDF storage exists
mkdir -p "$PDF_STORAGE_PATH"

# Log start
echo "$(date '+%Y-%m-%d %H:%M:%S') Starting receipt ingestion..."

# Run with venv
"$SCRIPT_DIR/.venv/bin/python" "$SCRIPT_DIR/receipt_ingestion.py" "$@"

echo "$(date '+%Y-%m-%d %H:%M:%S') Receipt ingestion complete."
