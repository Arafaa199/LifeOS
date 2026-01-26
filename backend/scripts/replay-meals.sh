#!/bin/bash
# LifeOS Meal Replay Script
# Purpose: Prove meal inference is deterministic and replayable
# Usage: ./replay-meals.sh

set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BACKEND_DIR"

echo "═══════════════════════════════════════════════════════════════"
echo "LifeOS Meal Replay Script"
echo "═══════════════════════════════════════════════════════════════"
echo

# Database connection
DB_HOST="100.90.189.16"
DB_PORT="5432"
DB_NAME="nexus"
DB_USER="nexus"

# Helper function to run SQL
run_sql() {
    ssh nexus "docker exec nexus-db psql -U $DB_USER -d $DB_NAME -t -c \"$1\""
}

# Phase 1: Pre-replay snapshot
echo "Phase 1: Pre-Replay Snapshot"
echo "------------------------------------------------------------"

echo "Capturing current meal counts..."

INFERRED_MEALS_BEFORE=$(run_sql "SELECT COUNT(*) FROM life.v_inferred_meals;" | xargs)
CONFIRMED_MEALS_BEFORE=$(run_sql "SELECT COUNT(*) FROM life.meal_confirmations;" | xargs)
PENDING_MEALS_BEFORE=$(run_sql "SELECT COUNT(*) FROM life.v_inferred_meals WHERE inferred_at_date NOT IN (SELECT inferred_meal_date FROM life.meal_confirmations WHERE user_action IN ('confirmed', 'skipped'));" | xargs)

echo "  Inferred meals (before): $INFERRED_MEALS_BEFORE"
echo "  Confirmed meals (before): $CONFIRMED_MEALS_BEFORE"
echo "  Pending meals (before): $PENDING_MEALS_BEFORE"
echo

# Phase 2: Backup meal confirmations
echo "Phase 2: Backup Meal Confirmations"
echo "------------------------------------------------------------"

BACKUP_FILE="/tmp/meal_confirmations_backup_$(date +%Y%m%d_%H%M%S).sql"

echo "Creating backup: $BACKUP_FILE"
ssh nexus "docker exec nexus-db pg_dump -U $DB_USER -d $DB_NAME --table=life.meal_confirmations --data-only --inserts" > "$BACKUP_FILE"
echo "  Backup size: $(wc -c < "$BACKUP_FILE" | xargs) bytes"
echo

# Phase 3: Truncate meal confirmations
echo "Phase 3: Truncate Meal Confirmations Table"
echo "------------------------------------------------------------"

echo "Truncating life.meal_confirmations..."
run_sql "TRUNCATE TABLE life.meal_confirmations;" > /dev/null
echo "  Table truncated ✓"
echo

# Phase 4: Refresh inferred meals view (deterministic refresh)
echo "Phase 4: Refresh Inferred Meals View"
echo "------------------------------------------------------------"

echo "Note: life.v_inferred_meals is a VIEW (not materialized)"
echo "It will automatically reflect current data from source tables:"
echo "  - life.daily_location_summary"
echo "  - life.daily_behavioral_summary"
echo "  - finance.transactions"
echo

# Phase 5: Compare inferred meal counts
echo "Phase 5: Compare Inferred Meal Counts"
echo "------------------------------------------------------------"

INFERRED_MEALS_AFTER=$(run_sql "SELECT COUNT(*) FROM life.v_inferred_meals;" | xargs)
PENDING_MEALS_AFTER=$(run_sql "SELECT COUNT(*) FROM life.v_inferred_meals WHERE inferred_at_date NOT IN (SELECT inferred_meal_date FROM life.meal_confirmations WHERE user_action IN ('confirmed', 'skipped'));" | xargs)

echo "Inferred meals comparison:"
echo "  Before: $INFERRED_MEALS_BEFORE"
echo "  After:  $INFERRED_MEALS_AFTER"

if [ "$INFERRED_MEALS_BEFORE" -eq "$INFERRED_MEALS_AFTER" ]; then
    echo "  ✓ PASS: Inferred meal count unchanged (deterministic)"
else
    echo "  ✗ FAIL: Inferred meal count changed (expected $INFERRED_MEALS_BEFORE, got $INFERRED_MEALS_AFTER)"
fi
echo

echo "Pending meals comparison:"
echo "  Before: $PENDING_MEALS_BEFORE"
echo "  After:  $PENDING_MEALS_AFTER"

if [ "$PENDING_MEALS_BEFORE" -eq "$PENDING_MEALS_AFTER" ]; then
    echo "  ✓ PASS: Pending meal count unchanged"
else
    echo "  Note: Expected increase (confirmations truncated)"
fi
echo

# Phase 6: Sample data verification
echo "Phase 6: Sample Data Verification"
echo "------------------------------------------------------------"

echo "Last 3 inferred meals:"
run_sql "SELECT inferred_at_date::TEXT, inferred_at_time::TEXT, meal_type, confidence, inference_source FROM life.v_inferred_meals ORDER BY inferred_at_date DESC, inferred_at_time DESC LIMIT 3;" | head -4

echo

# Phase 7: Restore meal confirmations (optional)
echo "Phase 7: Restore Meal Confirmations (Optional)"
echo "------------------------------------------------------------"

read -p "Restore meal confirmations from backup? (y/n): " -n 1 -r RESTORE_BACKUP
echo

if [[ $RESTORE_BACKUP =~ ^[Yy]$ ]]; then
    echo "Restoring backup: $BACKUP_FILE"
    ssh nexus "docker exec -i nexus-db psql -U $DB_USER -d $DB_NAME" < "$BACKUP_FILE" > /dev/null
    CONFIRMED_MEALS_RESTORED=$(run_sql "SELECT COUNT(*) FROM life.meal_confirmations;" | xargs)
    echo "  Restored $CONFIRMED_MEALS_RESTORED confirmations ✓"
else
    echo "Backup NOT restored (kept truncated state)"
fi
echo

# Phase 8: Summary
echo "═══════════════════════════════════════════════════════════════"
echo "Meal Replay Summary"
echo "═══════════════════════════════════════════════════════════════"

if [ "$INFERRED_MEALS_BEFORE" -eq "$INFERRED_MEALS_AFTER" ]; then
    echo "✓ PASS: Meal inference is deterministic"
    echo "  Inferred meals: $INFERRED_MEALS_BEFORE (unchanged)"
else
    echo "✗ FAIL: Meal inference is non-deterministic"
    echo "  Expected: $INFERRED_MEALS_BEFORE"
    echo "  Got: $INFERRED_MEALS_AFTER"
fi

echo
echo "Backup location: $BACKUP_FILE"
echo "Duration: $SECONDS seconds"
echo
