#!/bin/bash
# Finance Config Importer - Loads finance_config.yaml into Nexus DB
# Idempotent: uses external_id for upserts
# Usage: ./import_finance_config.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/finance_config.yaml"
SQL_FILE="$SCRIPT_DIR/sql/030_finance_controls.up.sql"
NEXUS_HOST="nexus"
DRY_RUN="${1:-}"

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# Check if yq is available (YAML parser)
if ! command -v yq &> /dev/null; then
    log "ERROR: yq not found. Install with: brew install yq"
    exit 1
fi

log "=== Finance Config Import ==="
log "Config: $CONFIG_FILE"

# First, apply the migration if not already applied
log "Applying migration..."
if [[ "$DRY_RUN" == "--dry-run" ]]; then
    log "[DRY RUN] Would apply: $SQL_FILE"
else
    ssh $NEXUS_HOST "docker exec -i nexus-db psql -U nexus -d nexus" < "$SQL_FILE" 2>&1 || true
fi

# Generate SQL for cashflow events
log "Importing cashflow events..."
EVENTS_SQL=""
while IFS= read -r line; do
    date=$(echo "$line" | yq -r '.date')
    event=$(echo "$line" | yq -r '.event' | sed "s/'/''/g")
    amount=$(echo "$line" | yq -r '.amount')
    type=$(echo "$line" | yq -r '.type')
    priority=$(echo "$line" | yq -r '.priority // "medium"')
    notes=$(echo "$line" | yq -r '.notes // ""' | sed "s/'/''/g")
    external_id="import-event-$(echo "$event" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')-$date"

    EVENTS_SQL+="SELECT finance.import_cashflow_event('$external_id', '$date', '$event', $amount, '$type', '$priority', '$notes');\n"
done < <(yq -c '.cashflow_events[]' "$CONFIG_FILE")

# Generate SQL for wishlist items
log "Importing wishlist items..."
WISHLIST_SQL=""
while IFS= read -r line; do
    item=$(echo "$line" | yq -r '.item' | sed "s/'/''/g")
    cost=$(echo "$line" | yq -r '.estimated_cost')
    priority=$(echo "$line" | yq -r '.priority // "medium"')
    category=$(echo "$line" | yq -r '.category // null')
    target=$(echo "$line" | yq -r '.target_date // null')
    notes=$(echo "$line" | yq -r '.notes // ""' | sed "s/'/''/g")
    external_id="import-wishlist-$(echo "$item" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-')"

    if [[ "$target" == "null" ]]; then
        target="NULL"
    else
        target="'$target'"
    fi

    if [[ "$category" == "null" ]]; then
        category="NULL"
    else
        category="'$category'"
    fi

    WISHLIST_SQL+="SELECT finance.import_wishlist_item('$external_id', '$item', $cost, '$priority', $category, $target, '$notes');\n"
done < <(yq -c '.wishlist[]' "$CONFIG_FILE")

# Generate SQL for budgets (upsert by month/category)
log "Importing budgets..."
BUDGET_SQL=""
current_month=$(date '+%Y-%m-01')
while IFS= read -r line; do
    category=$(echo "$line" | yq -r '.category' | sed "s/'/''/g")
    amount=$(echo "$line" | yq -r '.amount')
    notes=$(echo "$line" | yq -r '.notes // ""' | sed "s/'/''/g")

    BUDGET_SQL+="INSERT INTO finance.budgets (month, category, budget_amount, notes)
VALUES ('$current_month', '$category', $amount, '$notes')
ON CONFLICT (month, category) DO UPDATE SET budget_amount = EXCLUDED.budget_amount, notes = EXCLUDED.notes, updated_at = NOW();\n"
done < <(yq -c '.budgets[]' "$CONFIG_FILE")

# Generate SQL for recurring items
log "Importing recurring items..."
RECURRING_SQL=""
while IFS= read -r line; do
    name=$(echo "$line" | yq -r '.name' | sed "s/'/''/g")
    amount=$(echo "$line" | yq -r '.amount')
    frequency=$(echo "$line" | yq -r '.frequency')
    due_day=$(echo "$line" | yq -r '.due_day // null')
    due_date=$(echo "$line" | yq -r '.due_date // null')
    category=$(echo "$line" | yq -r '.category // null' | sed "s/'/''/g")
    notes=$(echo "$line" | yq -r '.notes // ""' | sed "s/'/''/g")

    # Map frequency to cadence
    cadence="$frequency"

    # Determine due_day and next_due_date
    if [[ "$due_day" != "null" ]]; then
        day_of_month="$due_day"
        next_due="MAKE_DATE(EXTRACT(YEAR FROM CURRENT_DATE)::int, EXTRACT(MONTH FROM CURRENT_DATE)::int, $due_day)"
    elif [[ "$due_date" != "null" ]]; then
        day_of_month="EXTRACT(DAY FROM '$due_date'::date)::int"
        next_due="'$due_date'::date"
    else
        day_of_month="NULL"
        next_due="NULL"
    fi

    RECURRING_SQL+="INSERT INTO finance.recurring_items (name, amount, type, cadence, day_of_month, next_due_date, notes, is_active)
VALUES ('$name', $amount, 'expense', '$cadence', $day_of_month, $next_due, '$notes', true)
ON CONFLICT DO NOTHING;\n"
done < <(yq -c '.recurring_bills[]' "$CONFIG_FILE")

# Combine all SQL
FULL_SQL="BEGIN;\n\n-- Cashflow Events\n$EVENTS_SQL\n-- Wishlist Items\n$WISHLIST_SQL\n-- Budgets\n$BUDGET_SQL\n-- Recurring Items\n$RECURRING_SQL\nCOMMIT;\n"

if [[ "$DRY_RUN" == "--dry-run" ]]; then
    log "[DRY RUN] Generated SQL:"
    echo -e "$FULL_SQL"
else
    log "Executing import..."
    echo -e "$FULL_SQL" | ssh $NEXUS_HOST "docker exec -i nexus-db psql -U nexus -d nexus"
    log "Import complete!"
fi

# Verification
if [[ "$DRY_RUN" != "--dry-run" ]]; then
    log "Verification:"
    ssh $NEXUS_HOST "docker exec nexus-db psql -U nexus -d nexus -c \"
SELECT 'cashflow_events' as table_name, COUNT(*) as count FROM finance.cashflow_events
UNION ALL
SELECT 'wishlist', COUNT(*) FROM finance.wishlist
UNION ALL
SELECT 'budgets', COUNT(*) FROM finance.budgets WHERE month = DATE_TRUNC('month', CURRENT_DATE)
UNION ALL
SELECT 'recurring_items', COUNT(*) FROM finance.recurring_items WHERE is_active = true;
\""
fi

log "=== Done ==="
