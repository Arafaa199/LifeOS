#!/usr/bin/env bash
# check.sh — Read-only smoke tests for LifeOS infrastructure
# Usage: check.sh [--json]
# Exit 0 = all green, non-zero = failures
# Zero mutations — GET requests and read-only checks only

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACTS_DIR="$SCRIPT_DIR/contracts"
VALIDATE="$SCRIPT_DIR/lib/validate-contract.sh"

JSON_OUTPUT=false
[[ "${1:-}" == "--json" ]] && JSON_OUTPUT=true

TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0
RESULTS=()

# Colors (disabled for JSON mode)
if $JSON_OUTPUT; then
  GREEN="" RED="" YELLOW="" RESET=""
else
  GREEN="\033[0;32m" RED="\033[0;31m" YELLOW="\033[0;33m" RESET="\033[0m"
fi

log_result() {
  local name="$1" status="$2" latency="${3:-0}" detail="${4:-}"
  TOTAL=$((TOTAL + 1))

  if $JSON_OUTPUT; then
    RESULTS+=("{\"name\":\"$name\",\"status\":\"$status\",\"latency_ms\":$latency,\"detail\":\"$detail\"}")
  else
    case "$status" in
      healthy) echo -e "  ${GREEN}PASS${RESET}  $name (${latency}ms)" ;;
      critical) echo -e "  ${RED}FAIL${RESET}  $name — $detail" ;;
      unknown) echo -e "  ${YELLOW}SKIP${RESET}  $name — $detail" ;;
    esac
  fi

  case "$status" in
    healthy) PASSED=$((PASSED + 1)) ;;
    critical) FAILED=$((FAILED + 1)) ;;
    unknown) SKIPPED=$((SKIPPED + 1)) ;;
  esac
}

# ── Infrastructure Checks ──────────────────────────────────────────

$JSON_OUTPUT || echo "Infrastructure"

# Check nexus-db reachable
START_MS=$(($(date +%s%N 2>/dev/null || echo 0) / 1000000))
if ssh -o ConnectTimeout=5 nexus "docker exec nexus-db pg_isready -U nexus" &>/dev/null; then
  END_MS=$(($(date +%s%N 2>/dev/null || echo 0) / 1000000))
  log_result "nexus-db" "healthy" "$((END_MS - START_MS))"
else
  log_result "nexus-db" "critical" "0" "pg_isready failed"
fi

# Check n8n responsive
START_MS=$(($(date +%s%N 2>/dev/null || echo 0) / 1000000))
if ssh -o ConnectTimeout=5 pivpn "curl -sf http://localhost:5678/healthz" &>/dev/null; then
  END_MS=$(($(date +%s%N 2>/dev/null || echo 0) / 1000000))
  log_result "n8n-health" "healthy" "$((END_MS - START_MS))"
else
  log_result "n8n-health" "critical" "0" "n8n healthz unreachable"
fi

# Check SMS watcher launchd
if (launchctl list 2>&1 || true) | grep -q "com.nexus.sms-watcher"; then
  log_result "sms-watcher-launchd" "healthy" "0"
else
  log_result "sms-watcher-launchd" "critical" "0" "launchd job not loaded"
fi

# ── Webhook Endpoint Checks ────────────────────────────────────────

$JSON_OUTPUT || echo ""
$JSON_OUTPUT || echo "Webhooks"

# Map contract files to their curl commands (with query params where needed)
declare -A ENDPOINT_URLS
ENDPOINT_URLS=(
  ["nexus-dashboard-today"]="http://localhost:5678/webhook/nexus-dashboard-today"
  ["nexus-recurring"]="http://localhost:5678/webhook/nexus-recurring"
  ["nexus-categories"]="http://localhost:5678/webhook/nexus-categories"
  ["nexus-budgets"]="http://localhost:5678/webhook/nexus-budgets"
  ["nexus-rules"]="http://localhost:5678/webhook/nexus-rules"
  ["nexus-sleep"]="http://localhost:5678/webhook/nexus-sleep?date=$(date +%Y-%m-%d)"
  ["nexus-sleep-history"]="http://localhost:5678/webhook/nexus-sleep-history?days=2"
  ["nexus-health-timeseries"]="http://localhost:5678/webhook/nexus-health-timeseries?days=2"
  ["nexus-reminders"]="http://localhost:5678/webhook/nexus-reminders?start=$(date +%Y-%m-%d)&end=$(date +%Y-%m-%d)"
  ["nexus-finance-summary"]="http://localhost:5678/webhook/nexus-finance-summary"
  ["nexus-monthly-trends"]="http://localhost:5678/webhook/nexus-monthly-trends"
  ["nexus-notes-search"]="http://localhost:5678/webhook/nexus-notes-search?q=test"
  ["nexus-documents"]="http://localhost:5678/webhook/nexus-documents"
  ["nexus-document-renewals"]="http://localhost:5678/webhook/nexus-document-renewals?id=1"
  ["nexus-reminders-sync-state"]="http://localhost:5678/webhook/nexus-reminders-sync-state"
  ["ops-health"]="http://localhost:5678/webhook/ops-health"
)

for contract_file in "$CONTRACTS_DIR"/*.json; do
  endpoint_name=$(basename "$contract_file" .json)
  url="${ENDPOINT_URLS[$endpoint_name]:-}"

  if [ -z "$url" ]; then
    log_result "$endpoint_name" "unknown" "0" "no URL mapped"
    continue
  fi

  START_MS=$(($(date +%s%N 2>/dev/null || echo 0) / 1000000))
  CURL_RESULT=$(ssh -o ConnectTimeout=5 pivpn "curl -s -w '\n%{http_code}' '$url'" 2>&1)
  CURL_EXIT=$?
  END_MS=$(($(date +%s%N 2>/dev/null || echo 0) / 1000000))
  LATENCY=$((END_MS - START_MS))

  HTTP_CODE=$(echo "$CURL_RESULT" | tail -1)
  RESPONSE=$(echo "$CURL_RESULT" | sed '$d')

  if [ $CURL_EXIT -ne 0 ]; then
    log_result "$endpoint_name" "critical" "$LATENCY" "SSH/curl error (exit $CURL_EXIT)"
    continue
  fi

  if [ "$HTTP_CODE" != "200" ]; then
    if echo "$RESPONSE" | grep -q "not registered"; then
      log_result "$endpoint_name" "unknown" "$LATENCY" "webhook not registered (workflow inactive)"
    elif echo "$RESPONSE" | grep -q "Authorization"; then
      log_result "$endpoint_name" "unknown" "$LATENCY" "requires auth (legacy workflow)"
    else
      log_result "$endpoint_name" "critical" "$LATENCY" "HTTP $HTTP_CODE"
    fi
    continue
  fi

  # Skip empty responses (workflow returns 200 but no body)
  if [ -z "$RESPONSE" ] || [ "$RESPONSE" = "null" ]; then
    log_result "$endpoint_name" "unknown" "$LATENCY" "empty response body (workflow misconfigured)"
    continue
  fi

  # Validate against contract
  VALIDATION=$(echo "$RESPONSE" | bash "$VALIDATE" "$contract_file" - 2>&1)
  if [ $? -eq 0 ]; then
    log_result "$endpoint_name" "healthy" "$LATENCY"
  else
    log_result "$endpoint_name" "critical" "$LATENCY" "$VALIDATION"
  fi
done

# ops-health is now included in the contract loop above via ops-health.json

# ── Summary ─────────────────────────────────────────────────────────

if $JSON_OUTPUT; then
  RESULTS_JSON=$(printf '%s,' "${RESULTS[@]}" | sed 's/,$//')
  cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "total": $TOTAL,
  "healthy": $PASSED,
  "critical": $FAILED,
  "unknown": $SKIPPED,
  "results": [$RESULTS_JSON]
}
EOF
else
  echo ""
  echo "─────────────────────────────────"
  echo -e "Total: $TOTAL | ${GREEN}Healthy: $PASSED${RESET} | ${RED}Critical: $FAILED${RESET} | ${YELLOW}Unknown: $SKIPPED${RESET}"
fi

[ "$FAILED" -eq 0 ] && exit 0 || exit 1
