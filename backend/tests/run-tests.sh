#!/usr/bin/env bash
# SQL Test Runner for LifeOS backend
# Usage: ./run-tests.sh [test_file_pattern]
# Examples:
#   ./run-tests.sh              # Run all tests
#   ./run-tests.sh 011          # Run only timezone tests
#   ./run-tests.sh timezone     # Run tests matching "timezone"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_HOST="${NEXUS_DB_HOST:-nexus}"
DB_USER="${NEXUS_DB_USER:-nexus}"
DB_NAME="${NEXUS_DB_NAME:-nexus}"
PATTERN="${1:-}"

passed=0
failed=0
skipped=0
failures=()

for test_file in "$SCRIPT_DIR"/*.sql; do
    name="$(basename "$test_file")"

    # Filter by pattern if provided
    if [[ -n "$PATTERN" ]] && [[ "$name" != *"$PATTERN"* ]]; then
        ((skipped++))
        continue
    fi

    printf "%-50s " "$name"

    output=$(ssh "$DB_HOST" "docker exec nexus-db psql -U $DB_USER -d $DB_NAME -v ON_ERROR_STOP=1" < "$test_file" 2>&1) && status=0 || status=$?

    if [[ $status -eq 0 ]]; then
        echo "PASS"
        ((passed++))
    else
        echo "FAIL"
        ((failed++))
        failures+=("$name")
        # Show first 10 lines of error
        echo "$output" | grep -i -E "error|fail|assert" | head -10 | sed 's/^/  /'
    fi
done

echo ""
echo "Results: $passed passed, $failed failed, $skipped skipped"

if [[ ${#failures[@]} -gt 0 ]]; then
    echo "Failed:"
    for f in "${failures[@]}"; do
        echo "  - $f"
    done
    exit 1
fi
