#!/bin/bash

# Auto SMS Import - Run this to automatically import bank transactions
# This script reads SMS messages from macOS Messages app and imports to Nexus

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/../logs/sms-import.log"
mkdir -p "$(dirname "$LOG_FILE")"

echo "[$(date)] Starting automatic SMS import..." >> "$LOG_FILE"

# Load environment variables
if [ -f "$SCRIPT_DIR/../.env" ]; then
    export $(grep -v '^#' "$SCRIPT_DIR/../.env" | xargs)
fi

# Run the import (last 7 days by default)
DAYS_BACK=${1:-7}

cd "$SCRIPT_DIR"
node import-sms-transactions.js "$DAYS_BACK" >> "$LOG_FILE" 2>&1

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "[$(date)] SMS import completed successfully" >> "$LOG_FILE"
else
    echo "[$(date)] SMS import failed with exit code $EXIT_CODE" >> "$LOG_FILE"
    # Optional: Send notification
    # curl -X POST https://n8n.rfanw/webhook/nexus-alert \
    #   -H "Content-Type: application/json" \
    #   -d '{"message":"SMS import failed","level":"error"}'
fi

# Trigger n8n to update daily summary
curl -s -X POST https://n8n.rfanw/webhook/nexus-refresh-summary > /dev/null 2>&1 || true

exit $EXIT_CODE
