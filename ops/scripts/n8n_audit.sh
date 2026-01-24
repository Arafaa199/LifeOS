#!/bin/bash
#
# n8n Workflow Audit Script
# Checks for violations of workflow rules
#
# Usage: ./n8n_audit.sh [--verbose]
#

set -e

VERBOSE="${1:-}"

log() {
    echo "[$(date +%H:%M:%S)] $1"
}

header() {
    echo ""
    echo "=== $1 ==="
}

# Check if we can reach n8n
check_n8n() {
    if ! ssh pivpn "docker exec n8n n8n list:workflow" &>/dev/null; then
        log "ERROR: Cannot reach n8n. Check SSH and Docker."
        exit 1
    fi
}

header "n8n Workflow Audit"
log "Fetching workflow data..."

check_n8n

# Export all workflows
WORKFLOWS=$(ssh pivpn "docker exec n8n n8n export:workflow --all" 2>/dev/null)

# Count totals
TOTAL=$(echo "$WORKFLOWS" | jq -r 'length')
ACTIVE=$(echo "$WORKFLOWS" | jq -r '[.[] | select(.active == true)] | length')
INACTIVE=$(echo "$WORKFLOWS" | jq -r '[.[] | select(.active == false)] | length')

log "Total workflows: $TOTAL (Active: $ACTIVE, Inactive: $INACTIVE)"

# Check 1: Multiple active workflows on same webhook path
header "Check 1: Duplicate Webhook Endpoints"

DUPLICATES=$(echo "$WORKFLOWS" | jq -r '
  [.[] | select(.active == true) |
   {id, name, path: (.nodes[] | select(.type == "n8n-nodes-base.webhook") | .parameters.path // "N/A")}] |
  group_by(.path) |
  map(select(length > 1)) |
  .[] |
  "  CONFLICT: /\(.[0].path) has \(length) active workflows:\n\(map("    - \(.id) | \(.name)") | join("\n"))"
' 2>/dev/null)

if [ -z "$DUPLICATES" ]; then
    log "✓ No duplicate endpoints found"
else
    log "✗ DUPLICATE ENDPOINTS FOUND:"
    echo "$DUPLICATES"
fi

# Check 2: Active workflows with problematic names
header "Check 2: Problematic Active Workflow Names"

PROBLEMATIC=$(echo "$WORKFLOWS" | jq -r '
  .[] |
  select(.active == true) |
  select(.name | test("(old|test|backup|debug|v[0-9])"; "i")) |
  "  WARNING: \(.id) | \(.name)"
' 2>/dev/null)

if [ -z "$PROBLEMATIC" ]; then
    log "✓ No problematic names found"
else
    log "✗ ACTIVE WORKFLOWS WITH PROBLEMATIC NAMES:"
    echo "$PROBLEMATIC"
fi

# Check 3: Endpoints without canonical owner
header "Check 3: Endpoint Coverage"

# Get all unique webhook paths with active workflows
ENDPOINTS=$(echo "$WORKFLOWS" | jq -r '
  [.[] | select(.active == true) |
   .nodes[] | select(.type == "n8n-nodes-base.webhook") |
   .parameters.path] |
  unique |
  sort |
  .[]
' 2>/dev/null)

ENDPOINT_COUNT=$(echo "$ENDPOINTS" | grep -c . || echo 0)
log "Active webhook endpoints: $ENDPOINT_COUNT"

if [ "$VERBOSE" == "--verbose" ]; then
    echo "$ENDPOINTS" | while read -r endpoint; do
        echo "  - /$endpoint"
    done
fi

# Check 4: /nexus-income status (critical endpoint)
header "Check 4: /nexus-income Canonical Status"

INCOME_ACTIVE=$(echo "$WORKFLOWS" | jq -r '
  [.[] | select(.active == true) |
   select(.nodes[] | select(.type == "n8n-nodes-base.webhook") | .parameters.path == "nexus-income")] |
  length
' 2>/dev/null)

INCOME_INACTIVE=$(echo "$WORKFLOWS" | jq -r '
  [.[] | select(.active == false) |
   select(.nodes[] | select(.type == "n8n-nodes-base.webhook") | .parameters.path == "nexus-income")] |
  length
' 2>/dev/null)

if [ "$INCOME_ACTIVE" == "1" ]; then
    INCOME_NAME=$(echo "$WORKFLOWS" | jq -r '
      .[] | select(.active == true) |
      select(.nodes[] | select(.type == "n8n-nodes-base.webhook") | .parameters.path == "nexus-income") |
      "\(.id) | \(.name)"
    ' 2>/dev/null)
    log "✓ /nexus-income has exactly 1 active workflow:"
    echo "  - $INCOME_NAME"
    log "  (Plus $INCOME_INACTIVE inactive workflows)"
else
    log "✗ /nexus-income has $INCOME_ACTIVE active workflows (expected: 1)"
fi

# Summary
header "Audit Summary"

ISSUES=0
[ -n "$DUPLICATES" ] && ISSUES=$((ISSUES + 1))
[ -n "$PROBLEMATIC" ] && ISSUES=$((ISSUES + 1))
[ "$INCOME_ACTIVE" != "1" ] && ISSUES=$((ISSUES + 1))

if [ $ISSUES -eq 0 ]; then
    log "✓ ALL CHECKS PASSED"
    exit 0
else
    log "✗ $ISSUES ISSUE(S) FOUND"
    exit 1
fi
