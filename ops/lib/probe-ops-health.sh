#!/usr/bin/env bash
# probe-ops-health.sh — Query ops-health endpoint, save response
# ops-health now emits healthy|stale|critical natively

set -uo pipefail

RESPONSE=$(ssh -o ConnectTimeout=5 pivpn "curl -sf http://localhost:5678/webhook/ops-health" 2>&1)
CURL_EXIT=$?

if [ $CURL_EXIT -ne 0 ]; then
  cat <<EOF
{
  "status": "critical",
  "error": "ops-health endpoint unreachable (exit $CURL_EXIT)",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  exit 1
fi

# Pass through — ops-health SQL already emits healthy|stale|critical
echo "$RESPONSE" | jq '. + {"source": "ops-health-probe"}'
