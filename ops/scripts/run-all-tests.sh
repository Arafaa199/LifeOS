#!/bin/bash
#
# Master Test Runner for LifeOS
# Runs all test suites: SQL, Webhooks, SMS Parser, E2E
#
# Usage: ./run-all-tests.sh [--skip-sql] [--skip-webhook] [--skip-sms] [--skip-e2e]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="${HOME}/Cyber/Dev/LifeOS/backend"
OPS_DIR="${HOME}/Cyber/Dev/LifeOS/ops"

LOG_DIR="${OPS_DIR}/logs/auditor"
LOG_FILE="${LOG_DIR}/full-test-run-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$LOG_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
SKIP_SQL=false
SKIP_WEBHOOK=false
SKIP_SMS=false
SKIP_E2E=false

for arg in "$@"; do
    case $arg in
        --skip-sql) SKIP_SQL=true ;;
        --skip-webhook) SKIP_WEBHOOK=true ;;
        --skip-sms) SKIP_SMS=true ;;
        --skip-e2e) SKIP_E2E=true ;;
        --help)
            echo "Usage: $0 [--skip-sql] [--skip-webhook] [--skip-sms] [--skip-e2e]"
            exit 0
            ;;
    esac
done

log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

header() {
    log ""
    log "${BLUE}========================================${NC}"
    log "${BLUE}$1${NC}"
    log "${BLUE}========================================${NC}"
}

# Tracking
SUITE_RESULTS=()

run_suite() {
    local name="$1"
    local result="$2"
    if [[ "$result" == "pass" ]]; then
        SUITE_RESULTS+=("${GREEN}[PASS]${NC} $name")
    elif [[ "$result" == "skip" ]]; then
        SUITE_RESULTS+=("${YELLOW}[SKIP]${NC} $name")
    else
        SUITE_RESULTS+=("${RED}[FAIL]${NC} $name")
    fi
}

# Start
log ""
log "${GREEN}LifeOS Full Test Suite${NC}"
log "Started: $(date)"
log "Log: $LOG_FILE"

# ==========================================
# 1. SQL Function Tests
# ==========================================
if [[ "$SKIP_SQL" == "false" ]]; then
    header "1. SQL Function Tests"

    SQL_TESTS=(
        "011_timezone_tests.sql"
        "012_categorization_trigger_tests.sql"
        "013_raw_immutability_tests.sql"
        "014_idempotency_tests.sql"
        "015_pipeline_verification_tests.sql"
        "020_data_integrity_tests.sql"
    )

    SQL_PASS=true
    for test_file in "${SQL_TESTS[@]}"; do
        test_path="${BACKEND_DIR}/tests/${test_file}"
        if [[ -f "$test_path" ]]; then
            log "Running: $test_file"
            if ssh nexus "docker exec -i nexus-db psql -U nexus -d nexus" < "$test_path" >> "$LOG_FILE" 2>&1; then
                log "${GREEN}[OK]${NC} $test_file"
            else
                log "${RED}[FAIL]${NC} $test_file"
                SQL_PASS=false
            fi
        else
            log "${YELLOW}[SKIP]${NC} $test_file (not found)"
        fi
    done

    if [[ "$SQL_PASS" == "true" ]]; then
        run_suite "SQL Function Tests" "pass"
    else
        run_suite "SQL Function Tests" "fail"
    fi
else
    run_suite "SQL Function Tests" "skip"
fi

# ==========================================
# 2. Webhook Availability Tests
# ==========================================
if [[ "$SKIP_WEBHOOK" == "false" ]]; then
    header "2. Webhook Availability Tests"

    WEBHOOK_SCRIPT="${OPS_DIR}/scripts/test-webhook-availability.sh"
    if [[ -x "$WEBHOOK_SCRIPT" ]]; then
        if "$WEBHOOK_SCRIPT" >> "$LOG_FILE" 2>&1; then
            run_suite "Webhook Tests" "pass"
        else
            run_suite "Webhook Tests" "fail"
        fi
    else
        log "${YELLOW}[SKIP]${NC} Webhook tests (script not found or not executable)"
        run_suite "Webhook Tests" "skip"
    fi
else
    run_suite "Webhook Tests" "skip"
fi

# ==========================================
# 3. SMS Parser Tests
# ==========================================
if [[ "$SKIP_SMS" == "false" ]]; then
    header "3. SMS Parser Tests"

    SMS_SCRIPT="${BACKEND_DIR}/scripts/test-sms-classifier.js"
    if [[ -f "$SMS_SCRIPT" ]]; then
        cd "${BACKEND_DIR}/scripts"
        if node test-sms-classifier.js >> "$LOG_FILE" 2>&1; then
            run_suite "SMS Parser Tests" "pass"
        else
            run_suite "SMS Parser Tests" "fail"
        fi
        cd - > /dev/null
    else
        log "${YELLOW}[SKIP]${NC} SMS tests (script not found)"
        run_suite "SMS Parser Tests" "skip"
    fi
else
    run_suite "SMS Parser Tests" "skip"
fi

# ==========================================
# 4. E2E Integration Tests
# ==========================================
if [[ "$SKIP_E2E" == "false" ]]; then
    header "4. E2E Integration Tests"

    E2E_SCRIPT="${OPS_DIR}/scripts/e2e-test-harness.sh"
    if [[ -x "$E2E_SCRIPT" ]]; then
        if "$E2E_SCRIPT" >> "$LOG_FILE" 2>&1; then
            run_suite "E2E Integration Tests" "pass"
        else
            run_suite "E2E Integration Tests" "fail"
        fi
    else
        log "${YELLOW}[SKIP]${NC} E2E tests (script not found or not executable)"
        run_suite "E2E Integration Tests" "skip"
    fi
else
    run_suite "E2E Integration Tests" "skip"
fi

# ==========================================
# Data Integrity Verification
# ==========================================
header "5. Quick Data Integrity Check"

log "Checking for duplicate client_ids..."
DUPE_CHECK=$(ssh nexus "docker exec nexus-db psql -U nexus -d nexus -t -c \"SELECT COUNT(*) FROM (SELECT client_id FROM finance.transactions WHERE client_id IS NOT NULL GROUP BY client_id HAVING COUNT(*) > 1) x;\"" 2>/dev/null | tr -d ' ')

if [[ "$DUPE_CHECK" == "0" ]]; then
    log "${GREEN}[OK]${NC} No duplicate client_ids"
    run_suite "Data Integrity" "pass"
else
    log "${RED}[FAIL]${NC} Found $DUPE_CHECK duplicate client_id groups"
    run_suite "Data Integrity" "fail"
fi

# ==========================================
# Summary
# ==========================================
header "SUMMARY"

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0

for result in "${SUITE_RESULTS[@]}"; do
    echo -e "$result" | tee -a "$LOG_FILE"
    if [[ "$result" == *"[PASS]"* ]]; then
        TOTAL_PASS=$((TOTAL_PASS + 1))
    elif [[ "$result" == *"[FAIL]"* ]]; then
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    else
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
    fi
done

log ""
log "Total: $((TOTAL_PASS + TOTAL_FAIL + TOTAL_SKIP)) suites"
log "Passed: $TOTAL_PASS"
log "Failed: $TOTAL_FAIL"
log "Skipped: $TOTAL_SKIP"
log ""
log "Completed: $(date)"
log "Full log: $LOG_FILE"

# ==========================================
# Cleanup reminder
# ==========================================
log ""
log "${YELLOW}Cleanup command (if needed):${NC}"
log "ssh nexus \"docker exec nexus-db psql -U nexus -d nexus -c \\\"DELETE FROM finance.transactions WHERE notes LIKE '%[TEST]%' OR client_id LIKE 'test-%' OR client_id LIKE 'e2e-test-%' OR client_id LIKE 'webhook-test-%';\\\"\""

# Exit code
if [[ $TOTAL_FAIL -gt 0 ]]; then
    log ""
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
else
    log ""
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
