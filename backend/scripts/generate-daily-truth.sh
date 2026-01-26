#!/bin/bash

# LifeOS Daily Truth Report Generator
# Generates markdown report showing if today's data is explainable
# Output: ops/artifacts/daily-truth-YYYY-MM-DD.md

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OPS_DIR="$(cd "$BACKEND_DIR/../ops" && pwd)"
ARTIFACTS_DIR="$OPS_DIR/artifacts"
DATE="${1:-$(date +%Y-%m-%d)}"
OUTPUT_FILE="$ARTIFACTS_DIR/daily-truth-$DATE.md"

# Database connection (via SSH to nexus)
DB_EXEC="ssh nexus docker exec nexus-db psql -U nexus -d nexus -t -A"

echo "════════════════════════════════════════════════════════════"
echo "LifeOS Daily Truth Report Generator"
echo "Date: $DATE"
echo "Output: $OUTPUT_FILE"
echo "════════════════════════════════════════════════════════════"

# Ensure artifacts directory exists
mkdir -p "$ARTIFACTS_DIR"

# Query coverage truth for the specified date
echo "Querying coverage truth for $DATE..."
COVERAGE_DATA=$(ssh nexus "docker exec nexus-db psql -U nexus -d nexus -t -A -c \"SELECT transactions_found || '|' || meals_found || '|' || inferred_meals || '|' || confirmed_meals || '|' || gap_status || '|' || COALESCE(explanation, '') FROM life.v_coverage_truth WHERE day = '$DATE'::DATE;\"")

# Parse coverage data
if [ -z "$COVERAGE_DATA" ] || [ "$COVERAGE_DATA" = "" ]; then
    echo "No coverage data found for $DATE (day not in last 30 days)"
    TRANSACTIONS=0
    MEALS=0
    INFERRED=0
    CONFIRMED=0
    GAP_STATUS="no_data"
    EXPLANATION="Date is outside the 30-day coverage window"
else
    TRANSACTIONS=$(echo "$COVERAGE_DATA" | cut -d'|' -f1)
    MEALS=$(echo "$COVERAGE_DATA" | cut -d'|' -f2)
    INFERRED=$(echo "$COVERAGE_DATA" | cut -d'|' -f3)
    CONFIRMED=$(echo "$COVERAGE_DATA" | cut -d'|' -f4)
    GAP_STATUS=$(echo "$COVERAGE_DATA" | cut -d'|' -f5)
    EXPLANATION=$(echo "$COVERAGE_DATA" | cut -d'|' -f6)
fi

# Determine if day is explainable
if [ "$GAP_STATUS" = "complete" ]; then
    STATUS="EXPLAINABLE"
    BLOCKERS=""
elif [ "$GAP_STATUS" = "expected_gap" ]; then
    STATUS="EXPLAINABLE"
    BLOCKERS=""
elif [ "$GAP_STATUS" = "gap" ]; then
    if [ -n "$EXPLANATION" ]; then
        STATUS="EXPLAINABLE"
        BLOCKERS=""
    else
        STATUS="NOT EXPLAINABLE"
        BLOCKERS="- Unexplained gap detected (no explanation provided)"
    fi
elif [ "$GAP_STATUS" = "no_data" ]; then
    STATUS="NOT EXPLAINABLE"
    BLOCKERS="- Date is outside the 30-day coverage window"
else
    STATUS="NOT EXPLAINABLE"
    BLOCKERS="- Unknown gap status: $GAP_STATUS"
fi

# Generate markdown report
cat > "$OUTPUT_FILE" <<MARKDOWN
# Daily Truth Report: $DATE

## Status: $STATUS

### Summary
- Transactions: $TRANSACTIONS
- Meals: $MEALS
- Inferred: $INFERRED
- Confirmed: $CONFIRMED

### Blockers (if not explainable)
$BLOCKERS

### Coverage

\`\`\`
Day: $DATE
Gap Status: $GAP_STATUS
Explanation: ${EXPLANATION:-None}
\`\`\`

---

**Generated:** $(date +"%Y-%m-%d %H:%M:%S %Z")
**Coverage Window:** Last 30 days
**View:** life.v_coverage_truth
MARKDOWN

echo "Report generated: $OUTPUT_FILE"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Status: $STATUS"
echo "Transactions: $TRANSACTIONS | Meals: $MEALS"
echo "Inferred: $INFERRED | Confirmed: $CONFIRMED"
echo "Gap Status: $GAP_STATUS"
echo "═══════════════════════════════════════════════════════════════"

# Exit with 0 if explainable, 1 if not
if [ "$STATUS" = "EXPLAINABLE" ]; then
    exit 0
else
    exit 1
fi
