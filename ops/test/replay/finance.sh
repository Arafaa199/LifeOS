#!/usr/bin/env bash
# finance.sh — Finance domain replay tests (SMS classifier)
# Part of ops/test/replay/ framework
# Usage: finance.sh [--json]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/../../../backend/scripts"
JSON_OUTPUT=false
[[ "${1:-}" == "--json" ]] && JSON_OUTPUT=true

DOMAIN="finance"

# Verify classifier exists
if [ ! -f "$BACKEND_DIR/sms-classifier.js" ]; then
  echo "ERROR: sms-classifier.js not found at $BACKEND_DIR"
  exit 1
fi

if [ ! -f "$BACKEND_DIR/test-sms-classifier.js" ]; then
  echo "ERROR: test-sms-classifier.js not found at $BACKEND_DIR"
  exit 1
fi

# Run classifier tests
OUTPUT=$(cd "$BACKEND_DIR" && node test-sms-classifier.js 2>&1)
EXIT_CODE=$?

# Parse results from output
TOTAL=$(echo "$OUTPUT" | grep "^Total:" | sed 's/Total: //')
PASSED=$(echo "$OUTPUT" | grep "^Passed:" | sed 's/Passed: //')
FAILED=$(echo "$OUTPUT" | grep "^Failed:" | sed 's/Failed: //')

STATUS="healthy"
[ "${FAILED:-0}" -gt 0 ] && STATUS="critical"

if $JSON_OUTPUT; then
  cat <<EOF
{
  "domain": "$DOMAIN",
  "test": "sms-classifier",
  "status": "$STATUS",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "total": ${TOTAL:-0},
  "passed": ${PASSED:-0},
  "failed": ${FAILED:-0},
  "exit_code": $EXIT_CODE
}
EOF
else
  echo "[$DOMAIN] SMS Classifier Replay"
  echo "$OUTPUT"
  echo ""
  echo "Status: $STATUS"
fi

exit $EXIT_CODE
