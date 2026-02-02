#!/usr/bin/env bash
# validate-contract.sh — Validate a JSON response against a contract schema
# Usage: validate-contract.sh <contract.json> <response.json|->
# Exit 0 = valid, Exit 1 = violations found
# Requires: jq

set -euo pipefail

CONTRACT="${1:?Usage: validate-contract.sh <contract.json> <response.json|->}"
RESPONSE="${2:--}"

if [ "$RESPONSE" = "-" ]; then
  RESPONSE_DATA=$(cat)
else
  RESPONSE_DATA=$(cat "$RESPONSE")
fi

if ! echo "$RESPONSE_DATA" | jq empty 2>/dev/null; then
  echo "FAIL: Response is not valid JSON"
  exit 1
fi

ENDPOINT=$(jq -r '.endpoint' "$CONTRACT")
VIOLATIONS=0

while IFS= read -r check; do
  path=$(echo "$check" | jq -r '.path')
  expected_type=$(echo "$check" | jq -r '.type')

  value=$(echo "$RESPONSE_DATA" | jq "$path" 2>/dev/null)

  if [ "$value" = "null" ] || [ -z "$value" ]; then
    echo "FAIL: $ENDPOINT — missing key: $path"
    VIOLATIONS=$((VIOLATIONS + 1))
    continue
  fi

  actual_type=$(echo "$RESPONSE_DATA" | jq -r "$path | type" 2>/dev/null)

  case "$expected_type" in
    boolean|string|array|object|null)
      if [ "$actual_type" != "$expected_type" ]; then
        echo "FAIL: $ENDPOINT — $path expected $expected_type, got $actual_type"
        VIOLATIONS=$((VIOLATIONS + 1))
      fi
      ;;
    number)
      if [ "$actual_type" != "number" ]; then
        echo "FAIL: $ENDPOINT — $path expected number, got $actual_type"
        VIOLATIONS=$((VIOLATIONS + 1))
      fi
      ;;
    *)
      echo "WARN: $ENDPOINT — unknown type '$expected_type' for $path"
      ;;
  esac
done < <(jq -c '.required_keys[]' "$CONTRACT")

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "RESULT: $VIOLATIONS violation(s) for $ENDPOINT"
  exit 1
fi

exit 0
