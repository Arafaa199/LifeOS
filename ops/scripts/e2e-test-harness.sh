#!/bin/bash
#
# E2E Test Harness for LifeOS Finance Webhooks
# Tests: income webhook, idempotency, raw_events tracking, validation statuses
#
# Usage: ./e2e-test-harness.sh [--cleanup]
#

set -e

TEST_PREFIX="e2e-test-$(date +%Y%m%d-%H%M%S)"
LOG_DIR="${HOME}/Cyber/Dev/LifeOS-Ops/logs/auditor"
LOG_FILE="${LOG_DIR}/e2e-test-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date +%H:%M:%S)] $1" | tee -a "$LOG_FILE"
}

header() {
    echo "" | tee -a "$LOG_FILE"
    echo "=== $1 ===" | tee -a "$LOG_FILE"
}

run_sql() {
    ssh nexus "docker exec nexus-db psql -U nexus -d nexus -c \"$1\"" 2>/dev/null
}

# n8n runs on pivpn - run curl via SSH
webhook_post() {
    local endpoint="$1"
    local data="$2"
    ssh pivpn "curl -s -X POST 'http://localhost:5678/webhook/${endpoint}' -H 'Content-Type: application/json' -d '${data}'" 2>/dev/null
}

# Verify that every valid raw_event has a transaction
verify_no_orphans() {
    local orphans=$(run_sql "SELECT COUNT(*) FROM finance.raw_events WHERE validation_status = 'valid' AND related_transaction_id IS NULL;" | grep -E '^\s*[0-9]+' | tr -d ' ')
    if [[ "$orphans" != "0" ]]; then
        log "✗ ORPHAN CHECK FAILED: $orphans valid events without transactions"
        return 1
    fi
    log "✓ No orphan valid events"
    return 0
}

# Verify no pending events stuck
verify_no_pending() {
    local pending=$(run_sql "SELECT COUNT(*) FROM finance.raw_events WHERE validation_status IN ('pending', 'processing') AND created_at < NOW() - INTERVAL '1 minute';" | grep -E '^\s*[0-9]+' | tr -d ' ')
    if [[ "$pending" != "0" ]]; then
        log "✗ PENDING CHECK FAILED: $pending events stuck in pending/processing"
        return 1
    fi
    log "✓ No stuck pending events"
    return 0
}

# Cleanup mode
if [[ "$1" == "--cleanup" ]]; then
    header "CLEANUP TEST DATA"
    log "Removing test transactions and raw_events..."
    run_sql "DELETE FROM finance.transactions WHERE client_id LIKE 'e2e-test-%';"
    run_sql "DELETE FROM finance.raw_events WHERE client_id LIKE 'e2e-test-%';"
    log "Cleanup complete"
    exit 0
fi

header "E2E TEST HARNESS - LifeOS Finance"
log "Test prefix: $TEST_PREFIX"
log "Log file: $LOG_FILE"

# Capture initial counts
header "PHASE 1: Baseline Counts"
INITIAL_TX=$(run_sql "SELECT COUNT(*) FROM finance.transactions;" | grep -E '^\s*[0-9]+' | tr -d ' ')
INITIAL_RAW=$(run_sql "SELECT COUNT(*) FROM finance.raw_events;" | grep -E '^\s*[0-9]+' | tr -d ' ')
log "Initial transactions: $INITIAL_TX"
log "Initial raw_events: $INITIAL_RAW"

# Test 1: Valid income with explicit amount
header "TEST 1: Valid Income (explicit amount)"
CLIENT_ID_1="${TEST_PREFIX}-income-1"
RESPONSE_1=$(webhook_post "nexus-income" "{\"client_id\": \"${CLIENT_ID_1}\", \"amount\": 1000, \"currency\": \"AED\", \"source\": \"E2E Test Income\", \"category\": \"Income\", \"notes\": \"Test income - explicit amount\"}")

log "Response: $RESPONSE_1"
SUCCESS_1=$(echo "$RESPONSE_1" | jq -r '.success // false')
IDEMPOTENT_1=$(echo "$RESPONSE_1" | jq -r '.idempotent // false')

if [[ "$SUCCESS_1" == "true" && "$IDEMPOTENT_1" == "false" ]]; then
    log "✓ TEST 1 PASSED: New income created"
else
    log "✗ TEST 1 FAILED: Expected success=true, idempotent=false"
    log "  Got success=$SUCCESS_1, idempotent=$IDEMPOTENT_1"
fi

# Test 2: Idempotency - same client_id should be duplicate
header "TEST 2: Idempotency Check (duplicate)"
RESPONSE_2=$(webhook_post "nexus-income" "{\"client_id\": \"${CLIENT_ID_1}\", \"amount\": 1000, \"currency\": \"AED\", \"source\": \"E2E Test Income\", \"category\": \"Income\"}")

log "Response: $RESPONSE_2"
SUCCESS_2=$(echo "$RESPONSE_2" | jq -r '.success // false')
IDEMPOTENT_2=$(echo "$RESPONSE_2" | jq -r '.idempotent // false')

if [[ "$SUCCESS_2" == "true" && "$IDEMPOTENT_2" == "true" ]]; then
    log "✓ TEST 2 PASSED: Duplicate detected correctly"
else
    log "✗ TEST 2 FAILED: Expected success=true, idempotent=true"
    log "  Got success=$SUCCESS_2, idempotent=$IDEMPOTENT_2"
fi

# Test 3: Income with raw_text parsing
header "TEST 3: Raw Text Parsing"
CLIENT_ID_3="${TEST_PREFIX}-income-3"
RESPONSE_3=$(webhook_post "nexus-income" "{\"client_id\": \"${CLIENT_ID_3}\", \"raw_text\": \"Salary deposit 5000 AED\", \"source\": \"E2E Test Salary\"}")

log "Response: $RESPONSE_3"
SUCCESS_3=$(echo "$RESPONSE_3" | jq -r '.success // false')
PARSED_AMOUNT=$(echo "$RESPONSE_3" | jq -r '.server_parsed.amount // 0')

if [[ "$SUCCESS_3" == "true" && "$PARSED_AMOUNT" == "5000" ]]; then
    log "✓ TEST 3 PASSED: Raw text parsed correctly (amount=5000)"
else
    log "✗ TEST 3 FAILED: Expected success=true, parsed_amount=5000"
    log "  Got success=$SUCCESS_3, parsed_amount=$PARSED_AMOUNT"
fi

# Test 4: Invalid request (missing client_id)
header "TEST 4: Validation (missing client_id)"
RESPONSE_4=$(webhook_post "nexus-income" "{\"amount\": 100, \"source\": \"Should Fail\"}")

log "Response: $RESPONSE_4"
SUCCESS_4=$(echo "$RESPONSE_4" | jq -r 'if .success == false then "false" else "true" end')
ERROR_4=$(echo "$RESPONSE_4" | jq -r '.error // ""')

if [[ "$SUCCESS_4" == "false" ]]; then
    log "✓ TEST 4 PASSED: Rejected missing client_id"
else
    log "✗ TEST 4 FAILED: Should have rejected missing client_id"
fi

# Test 5: Invalid amount
header "TEST 5: Validation (invalid amount)"
CLIENT_ID_5="${TEST_PREFIX}-invalid-5"
RESPONSE_5=$(webhook_post "nexus-income" "{\"client_id\": \"${CLIENT_ID_5}\", \"amount\": -100, \"source\": \"Negative Amount\"}")

log "Response: $RESPONSE_5"
SUCCESS_5=$(echo "$RESPONSE_5" | jq -r 'if .success == false then "false" else "true" end')

if [[ "$SUCCESS_5" == "false" ]]; then
    log "✓ TEST 5 PASSED: Rejected negative amount"
else
    log "✗ TEST 5 FAILED: Should have rejected negative amount"
fi

# Verify database state
header "PHASE 2: Database Verification"

# Check raw_events
log "Checking raw_events statuses..."
RAW_EVENTS=$(run_sql "SELECT client_id, validation_status, parsed_amount FROM finance.raw_events WHERE client_id LIKE '${TEST_PREFIX}%' ORDER BY created_at;")
log "Raw events:"
echo "$RAW_EVENTS" | tee -a "$LOG_FILE"

# Count by status
VALID_COUNT=$(run_sql "SELECT COUNT(*) FROM finance.raw_events WHERE client_id LIKE '${TEST_PREFIX}%' AND validation_status = 'valid';" | grep -E '^\s*[0-9]+' | tr -d ' ')
DUPLICATE_COUNT=$(run_sql "SELECT COUNT(*) FROM finance.raw_events WHERE client_id LIKE '${TEST_PREFIX}%' AND validation_status = 'duplicate';" | grep -E '^\s*[0-9]+' | tr -d ' ')
INVALID_COUNT=$(run_sql "SELECT COUNT(*) FROM finance.raw_events WHERE client_id LIKE '${TEST_PREFIX}%' AND validation_status = 'invalid';" | grep -E '^\s*[0-9]+' | tr -d ' ')

log "Status counts: valid=$VALID_COUNT, duplicate=$DUPLICATE_COUNT, invalid=$INVALID_COUNT"

# Check transactions
FINAL_TX=$(run_sql "SELECT COUNT(*) FROM finance.transactions;" | grep -E '^\s*[0-9]+' | tr -d ' ')
NEW_TX=$((FINAL_TX - INITIAL_TX))
log "New transactions created: $NEW_TX"

# Final raw_events count
FINAL_RAW=$(run_sql "SELECT COUNT(*) FROM finance.raw_events;" | grep -E '^\s*[0-9]+' | tr -d ' ')
NEW_RAW=$((FINAL_RAW - INITIAL_RAW))
log "New raw_events logged: $NEW_RAW"

# Integrity checks
header "INTEGRITY CHECKS"
INTEGRITY_PASS=true
verify_no_orphans || INTEGRITY_PASS=false
verify_no_pending || INTEGRITY_PASS=false

# Verify failed events have errors
FAILED_NO_ERRORS=$(run_sql "SELECT COUNT(*) FROM finance.raw_events WHERE validation_status = 'invalid' AND (validation_errors IS NULL OR array_length(validation_errors, 1) IS NULL);" | grep -E '^\s*[0-9]+' | tr -d ' ')
if [[ "$FAILED_NO_ERRORS" != "0" ]]; then
    log "✗ FAILED EVENTS CHECK: $FAILED_NO_ERRORS invalid events without error messages"
    INTEGRITY_PASS=false
else
    log "✓ All invalid events have error messages"
fi

# Summary
header "TEST SUMMARY"
TESTS_PASSED=0
TESTS_TOTAL=5

[[ "$SUCCESS_1" == "true" && "$IDEMPOTENT_1" == "false" ]] && TESTS_PASSED=$((TESTS_PASSED + 1)) || true
[[ "$SUCCESS_2" == "true" && "$IDEMPOTENT_2" == "true" ]] && TESTS_PASSED=$((TESTS_PASSED + 1)) || true
[[ "$SUCCESS_3" == "true" && "$PARSED_AMOUNT" == "5000" ]] && TESTS_PASSED=$((TESTS_PASSED + 1)) || true
[[ "$SUCCESS_4" == "false" ]] && TESTS_PASSED=$((TESTS_PASSED + 1)) || true
[[ "$SUCCESS_5" == "false" ]] && TESTS_PASSED=$((TESTS_PASSED + 1)) || true

log "Tests passed: $TESTS_PASSED / $TESTS_TOTAL"
log ""
log "Database changes:"
log "  - Transactions: $INITIAL_TX → $FINAL_TX (+$NEW_TX)"
log "  - Raw events:   $INITIAL_RAW → $FINAL_RAW (+$NEW_RAW)"
log "  - Valid:        $VALID_COUNT"
log "  - Duplicate:    $DUPLICATE_COUNT"
log "  - Invalid:      $INVALID_COUNT"

if [[ $TESTS_PASSED -eq $TESTS_TOTAL && "$INTEGRITY_PASS" == "true" ]]; then
    log ""
    log "✓ ALL TESTS PASSED"
    log "✓ ALL INTEGRITY CHECKS PASSED"
    exit 0
else
    log ""
    [[ $TESTS_PASSED -ne $TESTS_TOTAL ]] && log "✗ SOME TESTS FAILED ($TESTS_PASSED/$TESTS_TOTAL)"
    [[ "$INTEGRITY_PASS" != "true" ]] && log "✗ INTEGRITY CHECKS FAILED"
    exit 1
fi
