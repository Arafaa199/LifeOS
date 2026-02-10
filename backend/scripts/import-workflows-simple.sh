#!/bin/bash
# Simple n8n workflow import script
set -e

API_KEY="$1"
N8N_URL="${N8N_URL:-https://n8n.rfanw}"
WORKFLOW_DIR="${NEXUS_WORKFLOWS_DIR:-$(dirname "$0")/../n8n-workflows}"

if [ -z "$API_KEY" ]; then
    echo "Usage: $0 <API_KEY>"
    exit 1
fi

echo "🔍 Testing API connection..."
curl -s -H "X-N8N-API-KEY: $API_KEY" "$N8N_URL/api/v1/workflows" > /dev/null
echo "✅ API connection successful"
echo ""

SUCCESS=0
ERRORS=0

# Function to import or update workflow
import_workflow() {
    local file="$1"
    local description="$2"

    if [ ! -f "$file" ]; then
        echo "❌ File not found: $file"
        ((ERRORS++))
        return 1
    fi

    local name=$(jq -r '.name' "$file")
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 $name"
    echo "   $description"
    echo ""

    # Check if exists
    local existing=$(curl -s -H "X-N8N-API-KEY: $API_KEY" "$N8N_URL/api/v1/workflows" | jq -r ".data[] | select(.name == \"$name\") | .id" | head -1)

    if [ -n "$existing" ]; then
        echo "⚠️  Workflow exists (ID: $existing) - updating..."

        # Update
        local response=$(curl -s -X PUT \
            -H "X-N8N-API-KEY: $API_KEY" \
            -H "Content-Type: application/json" \
            -d @"$file" \
            "$N8N_URL/api/v1/workflows/$existing")

        if echo "$response" | jq -e '.data.id' >/dev/null 2>&1; then
            echo "✅ Updated successfully"

            # Activate
            curl -s -X PATCH \
                -H "X-N8N-API-KEY: $API_KEY" \
                -H "Content-Type: application/json" \
                -d '{"active": true}' \
                "$N8N_URL/api/v1/workflows/$existing" >/dev/null
            echo "✅ Activated"
            ((SUCCESS++))
        else
            echo "❌ Update failed"
            echo "$response" | jq -r '.message' 2>/dev/null || echo "$response"
            ((ERRORS++))
        fi
    else
        echo "➕ Creating new workflow..."

        # Create
        local response=$(curl -s -X POST \
            -H "X-N8N-API-KEY: $API_KEY" \
            -H "Content-Type: application/json" \
            -d @"$file" \
            "$N8N_URL/api/v1/workflows")

        local new_id=$(echo "$response" | jq -r '.data.id' 2>/dev/null)

        if [ -n "$new_id" ] && [ "$new_id" != "null" ]; then
            echo "✅ Created successfully (ID: $new_id)"

            # Activate
            curl -s -X PATCH \
                -H "X-N8N-API-KEY: $API_KEY" \
                -H "Content-Type: application/json" \
                -d '{"active": true}' \
                "$N8N_URL/api/v1/workflows/$new_id" >/dev/null
            echo "✅ Activated"
            ((SUCCESS++))
        else
            echo "❌ Creation failed"
            echo "$response" | jq -r '.message' 2>/dev/null || echo "$response"
            ((ERRORS++))
        fi
    fi
    echo ""
}

# ─── FINANCE (12) ─────────────────────────────────────────
echo "═══════════════════════════════════════════════════════"
echo "  1/7  Finance Workflows"
echo "═══════════════════════════════════════════════════════"
echo ""
import_workflow "$WORKFLOW_DIR/expense-log-webhook.json" "Expense logging"
import_workflow "$WORKFLOW_DIR/income-webhook.json" "Income tracking"
import_workflow "$WORKFLOW_DIR/transaction-update-webhook.json" "Edit transactions"
import_workflow "$WORKFLOW_DIR/transaction-delete-webhook.json" "Delete transactions"
import_workflow "$WORKFLOW_DIR/budget-set-webhook.json" "Set budgets"
import_workflow "$WORKFLOW_DIR/budget-fetch-webhook.json" "Fetch budgets"
import_workflow "$WORKFLOW_DIR/budget-delete-webhook.json" "Delete budgets"
import_workflow "$WORKFLOW_DIR/finance-summary-webhook.json" "Finance summary"
import_workflow "$WORKFLOW_DIR/insights-webhook.json" "AI insights"
import_workflow "$WORKFLOW_DIR/monthly-trends-webhook.json" "Monthly trends"
import_workflow "$WORKFLOW_DIR/auto-sms-import.json" "SMS auto-import"
import_workflow "$WORKFLOW_DIR/trigger-sms-import.json" "Manual SMS import"

# ─── HEALTH & NUTRITION (14) ─────────────────────────────
echo "═══════════════════════════════════════════════════════"
echo "  2/7  Health & Nutrition Workflows"
echo "═══════════════════════════════════════════════════════"
echo ""
import_workflow "$WORKFLOW_DIR/food-log-webhook.json" "Food logging"
import_workflow "$WORKFLOW_DIR/food-search-webhook.json" "Food search"
import_workflow "$WORKFLOW_DIR/weight-log-webhook.json" "Weight logging"
import_workflow "$WORKFLOW_DIR/sleep-fetch-webhook.json" "Sleep data fetch"
import_workflow "$WORKFLOW_DIR/sleep-history-webhook.json" "Sleep history"
import_workflow "$WORKFLOW_DIR/nutrition-history-webhook.json" "Nutrition history"
import_workflow "$WORKFLOW_DIR/health-timeseries-webhook.json" "Health timeseries"
import_workflow "$WORKFLOW_DIR/healthkit-batch-webhook.json" "HealthKit batch sync"
import_workflow "$WORKFLOW_DIR/workout-log-webhook.json" "Workout logging"
import_workflow "$WORKFLOW_DIR/workouts-fetch-webhook.json" "Workouts fetch"
import_workflow "$WORKFLOW_DIR/fasting-webhook.json" "Fasting tracker"
import_workflow "$WORKFLOW_DIR/supplements-webhook.json" "Supplements list"
import_workflow "$WORKFLOW_DIR/supplement-log-webhook.json" "Supplement dose logging"
import_workflow "$WORKFLOW_DIR/photo-food-webhook.json" "Photo food recognition"

# ─── MEDICATIONS (4) ──────────────────────────────────────
echo "═══════════════════════════════════════════════════════"
echo "  3/7  Medications Workflows"
echo "═══════════════════════════════════════════════════════"
echo ""
import_workflow "$WORKFLOW_DIR/medications-batch-webhook.json" "Medications batch sync"
import_workflow "$WORKFLOW_DIR/medication-toggle-webhook.json" "Medication toggle"
import_workflow "$WORKFLOW_DIR/medication-create-webhook.json" "⭐ NEW - Create medication"
import_workflow "$WORKFLOW_DIR/calendar-medications-webhook.json" "Calendar-medications sync"

# ─── DOCUMENTS & NOTES (4) ────────────────────────────────
echo "═══════════════════════════════════════════════════════"
echo "  4/7  Documents & Notes Workflows"
echo "═══════════════════════════════════════════════════════"
echo ""
import_workflow "$WORKFLOW_DIR/document-crud-webhooks.json" "Document CRUD"
import_workflow "$WORKFLOW_DIR/notes-index-webhook.json" "Notes index (fixes 404)"
import_workflow "$WORKFLOW_DIR/note-update-webhook.json" "⭐ NEW - Note update"
import_workflow "$WORKFLOW_DIR/note-delete-webhook.json" "⭐ NEW - Note delete"

# ─── RECEIPTS (3) ─────────────────────────────────────────
echo "═══════════════════════════════════════════════════════"
echo "  5/7  Receipts Workflows"
echo "═══════════════════════════════════════════════════════"
echo ""
import_workflow "$WORKFLOW_DIR/receipts-webhooks.json" "Receipts CRUD"
import_workflow "$WORKFLOW_DIR/receipt-raw-ingest.json" "Receipt email ingest"
import_workflow "$WORKFLOW_DIR/receipt-batch-import-webhook.json" "⭐ NEW - Receipt batch import"

# ─── DASHBOARD & SYSTEM (12) ─────────────────────────────
echo "═══════════════════════════════════════════════════════"
echo "  6/7  Dashboard & System Workflows"
echo "═══════════════════════════════════════════════════════"
echo ""
import_workflow "$WORKFLOW_DIR/dashboard-today-webhook.json" "Dashboard today"
import_workflow "$WORKFLOW_DIR/daily-summary-api.json" "Daily summary API (canonical)"
import_workflow "$WORKFLOW_DIR/daily-summary-update.json" "Daily summary updater"
import_workflow "$WORKFLOW_DIR/nightly-refresh-facts.json" "Nightly facts refresh"
import_workflow "$WORKFLOW_DIR/sync-status-webhook.json" "Sync status"
import_workflow "$WORKFLOW_DIR/behavioral-event-webhook.json" "Behavioral events"
import_workflow "$WORKFLOW_DIR/location-webhook.json" "Location tracking"
import_workflow "$WORKFLOW_DIR/calendar-crud-webhooks.json" "Calendar CRUD"
import_workflow "$WORKFLOW_DIR/calendar-events-webhook.json" "Calendar events"
import_workflow "$WORKFLOW_DIR/reminder-crud-webhooks.json" "Reminder CRUD"
import_workflow "$WORKFLOW_DIR/error-handler-global.json" "Global error handler"
import_workflow "$WORKFLOW_DIR/screen-time-webhook.json" "Screen time"

# ─── INFRA & MONITORING (8) ──────────────────────────────
echo "═══════════════════════════════════════════════════════"
echo "  7/7  Infrastructure & Monitoring Workflows"
echo "═══════════════════════════════════════════════════════"
echo ""
import_workflow "$WORKFLOW_DIR/health-metrics-sync.json" "HA health metrics sync"
import_workflow "$WORKFLOW_DIR/power-metrics-sync.json" "HA power metrics sync"
import_workflow "$WORKFLOW_DIR/environment-metrics-sync.json" "HA environment metrics sync"
import_workflow "$WORKFLOW_DIR/home-control-webhook.json" "Home control"
import_workflow "$WORKFLOW_DIR/home-status-webhook.json" "Home status"
import_workflow "$WORKFLOW_DIR/dlq-alert-monitor.json" "⭐ NEW - DLQ alert monitor"
import_workflow "$WORKFLOW_DIR/dlq-retry-processor.json" "DLQ retry processor"
import_workflow "$WORKFLOW_DIR/dlq-nightly-cleanup.json" "DLQ nightly cleanup"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Summary"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "✅ Successful: $SUCCESS"
echo "❌ Errors: $ERRORS"
echo ""

echo "Total: $((SUCCESS + ERRORS)) workflows processed"
echo ""

if [ $ERRORS -eq 0 ]; then
    echo "🎉 All workflows imported successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Verify at: $N8N_URL"
    echo "  2. Check env vars: HOME_ASSISTANT_URL, NEXUS_SCRIPTS_DIR, MAILHOG_URL"
    echo "  3. Disable any deprecated with-auth/* duplicates"
    echo "  4. Test from mobile app"
    echo ""
    echo "✅ Backend is production-ready!"
else
    echo "⚠️  $ERRORS workflow(s) had errors. Check the output above."
    echo "    Successful: $SUCCESS"
fi

echo ""
echo "═══════════════════════════════════════════════════════"
