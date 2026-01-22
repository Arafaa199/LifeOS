#!/bin/bash
set -e

LOG_DIR="${LOG_DIR:-/logs}"
LOG_FILE="$LOG_DIR/receipt-ingest.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Log function
log() {
    echo "[$(date -Iseconds)] $*" | tee -a "$LOG_FILE"
}

# Validate secrets exist
if [ ! -f "$SECRETS_DIR/gmail_client_secret.json" ]; then
    log "ERROR: Gmail client secret not found at $SECRETS_DIR/gmail_client_secret.json"
    exit 1
fi

if [ ! -f "$SECRETS_DIR/token.pickle" ]; then
    log "WARNING: Gmail token not found at $SECRETS_DIR/token.pickle"
    log "You may need to run initial OAuth flow manually"
fi

# Link secrets to app directory (where the script expects them)
ln -sf "$SECRETS_DIR/gmail_client_secret.json" /app/gmail_client_secret.json
ln -sf "$SECRETS_DIR/token.pickle" /app/token.pickle 2>/dev/null || true

# Override PDF storage path for server
export PDF_STORAGE_PATH="$DATA_DIR/receipts"

# Ensure data directory exists
mkdir -p "$PDF_STORAGE_PATH"

log "=== Receipt Ingestion Started ==="
log "Database: $NEXUS_HOST:$NEXUS_PORT/$NEXUS_DB"
log "Gmail Label: $GMAIL_LABEL"
log "Data Dir: $DATA_DIR"
log "Args: $*"

# Run the ingestion script with provided arguments, logging output
python /app/receipt_ingestion.py "$@" 2>&1 | tee -a "$LOG_FILE"
EXIT_CODE=${PIPESTATUS[0]}

log "=== Receipt Ingestion Finished (exit code: $EXIT_CODE) ==="
exit $EXIT_CODE
