#!/bin/bash

# Event-Based SMS Import
# Watches Messages database and imports immediately when new SMS arrives

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MESSAGES_DB="$HOME/Library/Messages/chat.db"
LOG_FILE="$SCRIPT_DIR/../logs/sms-watch.log"

mkdir -p "$(dirname "$LOG_FILE")"

echo "[$(date)] Starting Messages watcher..." | tee -a "$LOG_FILE"

# Load environment
if [ -f "$SCRIPT_DIR/../.env" ]; then
    export $(grep -v '^#' "$SCRIPT_DIR/../.env" | xargs)
fi

# Check if fswatch is installed
if ! command -v fswatch &> /dev/null; then
    echo "Installing fswatch..." | tee -a "$LOG_FILE"
    brew install fswatch
fi

echo "Watching: $MESSAGES_DB" | tee -a "$LOG_FILE"
echo "Press Ctrl+C to stop" | tee -a "$LOG_FILE"
echo ""

# Watch the Messages database for changes
fswatch -o "$MESSAGES_DB" | while read num
do
    echo "[$(date)] New message detected, importing..." | tee -a "$LOG_FILE"

    # Import only last few minutes (0.01 days = ~15 minutes)
    cd "$SCRIPT_DIR"
    node import-sms-transactions.js 0.01 >> "$LOG_FILE" 2>&1

    # Notify app via webhook (optional)
    curl -s -X POST https://n8n.rfanw/webhook/nexus-refresh-summary > /dev/null 2>&1 || true

    echo "[$(date)] Import complete" | tee -a "$LOG_FILE"
done
