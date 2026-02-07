#!/bin/bash
#
# Migration Transaction Audit Script
#
# Analyzes all migration files to identify which ones lack proper
# transaction wrappers (BEGIN/COMMIT). This is a documentation tool -
# it does NOT modify any files.
#
# Risk Assessment:
# - Migrations without BEGIN/COMMIT may leave the database in an
#   inconsistent state if they fail partway through.
# - PostgreSQL DDL is transactional, so multi-statement migrations
#   should be wrapped for atomicity.
#
# Usage: ./audit-migrations-transactions.sh
#

MIGRATIONS_DIR="$(dirname "$0")/../migrations"
OUTPUT_FILE="$(dirname "$0")/../docs/migration-transaction-audit.md"

# Ensure we're in the right place
if [ ! -d "$MIGRATIONS_DIR" ]; then
    echo "Error: Migrations directory not found at $MIGRATIONS_DIR"
    exit 1
fi

# Count totals
total_up=0
total_down=0
wrapped_up=0
wrapped_down=0
unwrapped_up=()
unwrapped_down=()

echo "Auditing migrations in $MIGRATIONS_DIR..."

# Check each .up.sql file
for file in "$MIGRATIONS_DIR"/*.up.sql; do
    [ -e "$file" ] || continue
    filename=$(basename "$file")
    total_up=$((total_up + 1))

    # Check for BEGIN at start (ignoring comments and whitespace)
    has_begin=$(grep -i "^\s*BEGIN\s*;" "$file" 2>/dev/null | head -1)
    has_commit=$(grep -i "^\s*COMMIT\s*;" "$file" 2>/dev/null | tail -1)

    if [ -n "$has_begin" ] && [ -n "$has_commit" ]; then
        wrapped_up=$((wrapped_up + 1))
    else
        unwrapped_up+=("$filename")
    fi
done

# Check each .down.sql file
for file in "$MIGRATIONS_DIR"/*.down.sql; do
    [ -e "$file" ] || continue
    filename=$(basename "$file")
    total_down=$((total_down + 1))

    has_begin=$(grep -i "^\s*BEGIN\s*;" "$file" 2>/dev/null | head -1)
    has_commit=$(grep -i "^\s*COMMIT\s*;" "$file" 2>/dev/null | tail -1)

    if [ -n "$has_begin" ] && [ -n "$has_commit" ]; then
        wrapped_down=$((wrapped_down + 1))
    else
        unwrapped_down+=("$filename")
    fi
done

# Generate report
mkdir -p "$(dirname "$OUTPUT_FILE")"

cat > "$OUTPUT_FILE" << EOF
# Migration Transaction Wrapper Audit

Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

## Summary

| Type | Total | Wrapped | Unwrapped | Coverage |
|------|-------|---------|-----------|----------|
| UP migrations | $total_up | $wrapped_up | $((total_up - wrapped_up)) | $(echo "scale=1; $wrapped_up * 100 / $total_up" | bc)% |
| DOWN migrations | $total_down | $wrapped_down | $((total_down - wrapped_down)) | $(echo "scale=1; $wrapped_down * 100 / $total_down" | bc)% |

## Risk Assessment

Migrations without transaction wrappers may leave the database in an inconsistent
state if they fail partway through execution. PostgreSQL DDL is transactional,
so multi-statement migrations should use \`BEGIN\` and \`COMMIT\` for atomicity.

**Impact of unwrapped migrations:**
- Partial application on failure requires manual cleanup
- No automatic rollback on error
- Potential for orphaned objects or missing constraints

**Recommendation:**
- New migrations should always include BEGIN/COMMIT
- Existing unwrapped migrations should be noted but NOT retroactively edited
  (editing applied migrations breaks the migration checksum/history)

## Unwrapped UP Migrations (${#unwrapped_up[@]} files)

$(if [ ${#unwrapped_up[@]} -eq 0 ]; then
    echo "None - all UP migrations are properly wrapped."
else
    printf '| File | Risk Notes |\n'
    printf '|------|------------|\n'
    for f in "${unwrapped_up[@]}"; do
        # Extract migration number
        num=$(echo "$f" | grep -oE '^[0-9]+')
        if [ "$num" -lt 50 ]; then
            risk="Low - early schema setup, likely simple"
        elif [ "$num" -lt 100 ]; then
            risk="Medium - established patterns, check complexity"
        else
            risk="Review - recent migration without wrapper"
        fi
        printf '| %s | %s |\n' "$f" "$risk"
    done
fi)

## Unwrapped DOWN Migrations (${#unwrapped_down[@]} files)

$(if [ ${#unwrapped_down[@]} -eq 0 ]; then
    echo "None - all DOWN migrations are properly wrapped."
else
    printf '| File | Risk Notes |\n'
    printf '|------|------------|\n'
    for f in "${unwrapped_down[@]}"; do
        printf '| %s | DOWN migrations are rarely executed |\n' "$f"
    done
fi)

## Best Practices for New Migrations

\`\`\`sql
-- Migration: NNN_description
-- Purpose: Brief description

BEGIN;

-- Your DDL statements here
CREATE TABLE ...;
ALTER TABLE ...;

-- Verification (optional)
-- SELECT ...;

COMMIT;
\`\`\`

## Notes

- This audit was generated automatically and may have false positives/negatives
- Some migrations intentionally avoid transactions (e.g., CREATE INDEX CONCURRENTLY)
- The audit checks for BEGIN/COMMIT keywords but doesn't validate structure
EOF

echo ""
echo "=== Migration Transaction Audit ==="
echo ""
echo "UP migrations:   $wrapped_up / $total_up wrapped ($(echo "scale=1; $wrapped_up * 100 / $total_up" | bc)%)"
echo "DOWN migrations: $wrapped_down / $total_down wrapped ($(echo "scale=1; $wrapped_down * 100 / $total_down" | bc)%)"
echo ""

if [ ${#unwrapped_up[@]} -gt 0 ]; then
    echo "Unwrapped UP migrations (${#unwrapped_up[@]}):"
    for f in "${unwrapped_up[@]}"; do
        echo "  - $f"
    done
    echo ""
fi

echo "Full report written to: $OUTPUT_FILE"
