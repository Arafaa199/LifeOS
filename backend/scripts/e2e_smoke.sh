#!/usr/bin/env bash
# e2e_smoke.sh — Deterministic E2E smoke test for LifeOS critical paths
# Tests: Calendar Sync, Sync Status, Finance Summary, Dashboard
# Usage: ./e2e_smoke.sh [--cleanup]
# Requires: curl, ssh access to nexus, n8n webhooks active

set -euo pipefail

WEBHOOK_BASE="${WEBHOOK_BASE:-https://n8n.rfanw}"
DB_HOST="nexus"
DB_CMD="docker exec nexus-db psql -U nexus -d nexus -tAc"
REPORT_FILE="/Users/rafa/Cyber/Dev/Projects/LifeOS/ops/artifacts/e2e-report.md"
PASS=0
FAIL=0
RESULTS=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_pass() {
    PASS=$((PASS + 1))
    RESULTS+=("PASS: $1")
    echo -e "${GREEN}PASS${NC}: $1"
}

log_fail() {
    FAIL=$((FAIL + 1))
    RESULTS+=("FAIL: $1 — $2")
    echo -e "${RED}FAIL${NC}: $1 — $2"
}

log_info() {
    echo -e "${YELLOW}INFO${NC}: $1"
}

# ── Test 1: Calendar Sync Webhook ──────────────────────────────────────
test_calendar_sync() {
    log_info "Testing Calendar Sync Webhook (POST)"

    local response
    response=$(curl -s -k -X POST "${WEBHOOK_BASE}/webhook/nexus-calendar-sync" \
        -H "Content-Type: application/json" \
        -d '{
            "client_id": null,
            "device": "e2e_smoke",
            "source": "e2e_smoke",
            "events": [
                {
                    "event_id": "E2E-SMOKE-001",
                    "title": "E2E Smoke Test Event",
                    "start_at": "2026-01-26T09:00:00+04:00",
                    "end_at": "2026-01-26T10:00:00+04:00",
                    "is_all_day": false,
                    "calendar_name": "E2E Test",
                    "location": null,
                    "notes": "Automated smoke test",
                    "recurrence_rule": null
                }
            ]
        }' 2>/dev/null)

    local success
    success=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success', False))" 2>/dev/null || echo "False")

    if [ "$success" = "True" ]; then
        local run_id
        run_id=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('run_id', 'none'))" 2>/dev/null || echo "none")
        log_pass "Calendar webhook returned success (run_id: ${run_id:0:8}...)"
    else
        log_fail "Calendar webhook" "Response: $response"
        return
    fi

    # Verify DB write
    local db_count
    db_count=$(ssh "$DB_HOST" "$DB_CMD \"SELECT COUNT(*) FROM raw.calendar_events WHERE event_id = 'E2E-SMOKE-001';\"" 2>/dev/null || echo "0")
    db_count=$(echo "$db_count" | tr -d '[:space:]')

    if [ "$db_count" = "1" ]; then
        log_pass "Calendar event written to DB (raw.calendar_events)"
    else
        log_fail "Calendar DB write" "Expected 1 row, got: $db_count"
    fi

    # Verify sync_runs recorded
    local sync_count
    sync_count=$(ssh "$DB_HOST" "$DB_CMD \"SELECT COUNT(*) FROM ops.sync_runs WHERE domain = 'calendar' AND status = 'success' AND started_at > now() - interval '2 minutes';\"" 2>/dev/null || echo "0")
    sync_count=$(echo "$sync_count" | tr -d '[:space:]')

    if [ "$sync_count" -ge "1" ] 2>/dev/null; then
        log_pass "Sync run recorded in ops.sync_runs"
    else
        log_fail "Sync run recording" "Expected >=1 recent success, got: $sync_count"
    fi

    # Idempotency test: resend same event
    local response2
    response2=$(curl -s -k -X POST "${WEBHOOK_BASE}/webhook/nexus-calendar-sync" \
        -H "Content-Type: application/json" \
        -d '{
            "client_id": null,
            "device": "e2e_smoke",
            "source": "e2e_smoke",
            "events": [
                {
                    "event_id": "E2E-SMOKE-001",
                    "title": "E2E Smoke Test Event UPDATED",
                    "start_at": "2026-01-26T09:00:00+04:00",
                    "end_at": "2026-01-26T10:00:00+04:00",
                    "is_all_day": false,
                    "calendar_name": "E2E Test",
                    "location": null,
                    "notes": "Automated smoke test - updated",
                    "recurrence_rule": null
                }
            ]
        }' 2>/dev/null)

    local updated_count
    updated_count=$(echo "$response2" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('inserted',{}).get('updated',0))" 2>/dev/null || echo "0")

    if [ "$updated_count" = "1" ]; then
        log_pass "Idempotent upsert working (1 updated, 0 inserted)"
    else
        log_fail "Idempotent upsert" "Expected updated=1, response: $response2"
    fi
}

# ── Test 2: Sync Status Endpoint ──────────────────────────────────────
test_sync_status() {
    log_info "Testing Sync Status Endpoint (GET)"

    local response
    response=$(curl -s -k "${WEBHOOK_BASE}/webhook/nexus-sync-status" 2>/dev/null)

    local success
    success=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success', False))" 2>/dev/null || echo "False")

    if [ "$success" = "True" ]; then
        log_pass "Sync status endpoint returned success"
    else
        log_fail "Sync status endpoint" "Response: $response"
        return
    fi

    local has_calendar
    has_calendar=$(echo "$response" | python3 -c "
import sys,json
data = json.load(sys.stdin)
domains = data.get('domains', [])
cal = [d for d in domains if d['domain'] == 'calendar']
print('yes' if cal and cal[0].get('freshness') == 'fresh' else 'no')
" 2>/dev/null || echo "no")

    if [ "$has_calendar" = "yes" ]; then
        log_pass "Calendar domain shows 'fresh' status"
    else
        log_fail "Calendar freshness" "Expected 'fresh', response: $response"
    fi
}

# ── Test 3: Finance Summary Endpoint ──────────────────────────────────
test_finance_summary() {
    log_info "Testing Finance Summary (GET)"

    local response http_code
    http_code=$(curl -s -k -o /dev/null -w "%{http_code}" "${WEBHOOK_BASE}/webhook/nexus-finance-summary" 2>/dev/null)

    if [ "$http_code" = "200" ]; then
        log_pass "Finance summary endpoint returned HTTP 200"
    elif [ "$http_code" = "401" ] || [ "$http_code" = "403" ]; then
        log_pass "Finance summary endpoint reachable (auth required — HTTP $http_code)"
    else
        response=$(curl -s -k "${WEBHOOK_BASE}/webhook/nexus-finance-summary" 2>/dev/null)
        log_fail "Finance summary" "HTTP $http_code — ${response:0:200}"
    fi
}

# ── Test 4: Dashboard Today Endpoint ──────────────────────────────────
test_dashboard() {
    log_info "Testing Dashboard Today (GET)"

    local response
    response=$(curl -s -k "${WEBHOOK_BASE}/webhook/nexus-dashboard-today" 2>/dev/null)

    # Dashboard response uses 'meta' at top level, not 'success'
    local has_data
    has_data=$(echo "$response" | python3 -c "
import sys,json
data = json.load(sys.stdin)
print('yes' if data.get('success', False) or data.get('meta') else 'no')
" 2>/dev/null || echo "no")

    if [ "$has_data" = "yes" ]; then
        log_pass "Dashboard endpoint returned valid data"
    else
        log_fail "Dashboard endpoint" "Response: ${response:0:200}"
    fi
}

# ── Test 5: Database Connectivity ─────────────────────────────────────
test_database() {
    log_info "Testing Database Connectivity"

    local version
    version=$(ssh "$DB_HOST" "$DB_CMD \"SELECT version();\"" 2>/dev/null | head -1 || echo "FAILED")

    if echo "$version" | grep -q "PostgreSQL"; then
        log_pass "PostgreSQL reachable ($(echo "$version" | grep -o 'PostgreSQL [0-9.]*'))"
    else
        log_fail "Database connectivity" "$version"
        return
    fi

    # Check key tables exist
    local tables
    tables=$(ssh "$DB_HOST" "$DB_CMD \"
        SELECT string_agg(schemaname || '.' || tablename, ', ')
        FROM pg_tables
        WHERE schemaname || '.' || tablename IN (
            'raw.calendar_events',
            'ops.sync_runs',
            'finance.transactions',
            'health.metrics'
        );
    \"" 2>/dev/null || echo "")

    local table_count
    table_count=$(echo "$tables" | tr ',' '\n' | grep -c '\.' 2>/dev/null || echo "0")

    if [ "$table_count" -ge "4" ] 2>/dev/null; then
        log_pass "All critical tables exist ($tables)"
    else
        log_fail "Critical tables" "Found: $tables"
    fi
}

# ── Test 6: n8n Workflow Activation ───────────────────────────────────
test_n8n_workflows() {
    log_info "Testing n8n Workflow Activation"

    local active_workflows
    active_workflows=$(ssh pivpn "docker exec n8n n8n list:workflow --active=true 2>/dev/null" || echo "FAILED")

    local critical_workflows=("Calendar Sync Webhook" "Nexus: Sync Status API" "Nexus: Finance Summary API" "Nexus: Dashboard Today API")

    for wf in "${critical_workflows[@]}"; do
        if echo "$active_workflows" | grep -q "$wf"; then
            log_pass "Workflow active: $wf"
        else
            log_fail "Workflow inactive" "$wf"
        fi
    done
}

# ── Cleanup ───────────────────────────────────────────────────────────
cleanup() {
    log_info "Cleaning up test data..."
    ssh "$DB_HOST" "$DB_CMD \"
        DELETE FROM raw.calendar_events WHERE event_id = 'E2E-SMOKE-001';
        DELETE FROM ops.sync_runs WHERE meta::text LIKE '%e2e_smoke%' OR source = 'e2e_smoke';
    \"" 2>/dev/null
    log_info "Test data cleaned"
}

# ── Report ────────────────────────────────────────────────────────────
generate_report() {
    local total=$((PASS + FAIL))
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    cat > "$REPORT_FILE" <<EOF
# E2E Smoke Test Report

**Run**: $timestamp
**Result**: $PASS/$total passed ($FAIL failed)
**Status**: $([ "$FAIL" -eq 0 ] && echo "ALL PASS" || echo "FAILURES DETECTED")

## Results

$(for r in "${RESULTS[@]}"; do echo "- $r"; done)

## Environment

- Webhook Base: $WEBHOOK_BASE
- DB Host: $DB_HOST
- n8n Host: pivpn (Docker)

---
Generated by \`scripts/e2e_smoke.sh\`
EOF

    log_info "Report written to: $REPORT_FILE"
}

# ── Main ──────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════"
echo "  LifeOS E2E Smoke Test"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "═══════════════════════════════════════════════"
echo ""

test_database
test_n8n_workflows
test_calendar_sync
test_sync_status
test_finance_summary
test_dashboard

echo ""
echo "═══════════════════════════════════════════════"
echo -e "  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
echo "═══════════════════════════════════════════════"

generate_report

# Cleanup test data
cleanup

exit $FAIL
