#!/usr/bin/env bash
# sms-replay.sh — SMS classifier replay harness
# Runs the existing test-sms-classifier.js and reports results in ops format
# Usage: sms-replay.sh [--json]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/../../backend/scripts"
JSON_OUTPUT=false
[[ "${1:-}" == "--json" ]] && JSON_OUTPUT=true

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

if $JSON_OUTPUT; then
  # Extract failure details if any
  FAILURES="[]"
  if [ "$EXIT_CODE" -ne 0 ]; then
    FAILURES=$(echo "$OUTPUT" | sed -n '/Failed Tests Details:/,$ p' | tail -n +2)
  fi

  cat <<EOF
{
  "test": "sms-classifier",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "total": ${TOTAL:-0},
  "passed": ${PASSED:-0},
  "failed": ${FAILED:-0},
  "exit_code": $EXIT_CODE
}
EOF
else
  echo "$OUTPUT"
fi

exit $EXIT_CODE
