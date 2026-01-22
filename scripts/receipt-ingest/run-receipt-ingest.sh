#!/bin/bash
# Receipt Ingestion Runner
# Uses Python venv for dependencies

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$SCRIPT_DIR/.venv"

# Activate venv and run
source "$VENV/bin/activate"
python3 "$SCRIPT_DIR/receipt_ingestion.py" "$@"
