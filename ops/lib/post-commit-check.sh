#!/usr/bin/env bash
# post-commit-check.sh — Advisory wrapper around check.sh
# Always exits 0 (advisory only, never blocks commits)
# Used by auditor to run checks after reviewing commits

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[ops] Running post-commit smoke tests..."
bash "$SCRIPT_DIR/check.sh" "$@" || true

exit 0
