#!/usr/bin/env bash
# all.sh — Run all domain replay tests
# Part of ops/test/replay/ framework
# Usage: all.sh [--json]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_OUTPUT=false
[[ "${1:-}" == "--json" ]] && JSON_OUTPUT=true

TOTAL=0
PASSED=0
FAILED=0
RESULTS=()

for test_script in "$SCRIPT_DIR"/*.sh; do
  [ "$(basename "$test_script")" = "all.sh" ] && continue
  [ ! -x "$test_script" ] && continue

  DOMAIN=$(basename "$test_script" .sh)
  TOTAL=$((TOTAL + 1))

  OUTPUT=$(bash "$test_script" --json 2>&1)
  EXIT_CODE=$?

  if [ $EXIT_CODE -eq 0 ]; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
  fi

  if $JSON_OUTPUT; then
    RESULTS+=("$OUTPUT")
  else
    STATUS=$(echo "$OUTPUT" | jq -r '.status' 2>/dev/null || echo "unknown")
    if [ $EXIT_CODE -eq 0 ]; then
      echo "  PASS  $DOMAIN ($STATUS)"
    else
      echo "  FAIL  $DOMAIN ($STATUS)"
    fi
  fi
done

if $JSON_OUTPUT; then
  RESULTS_JSON=$(printf '%s,' "${RESULTS[@]}" | sed 's/,$//')
  cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "total": $TOTAL,
  "healthy": $PASSED,
  "critical": $FAILED,
  "results": [$RESULTS_JSON]
}
EOF
else
  echo ""
  echo "Replay Tests: $TOTAL total | $PASSED passed | $FAILED failed"
fi

[ "$FAILED" -eq 0 ] && exit 0 || exit 1
