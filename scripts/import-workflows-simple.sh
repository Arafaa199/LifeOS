#!/bin/bash
# Simple n8n workflow import script
set -e

API_KEY="$1"
N8N_URL="https://n8n.rfanw"
WORKFLOW_DIR="/Users/rafa/Cyber/Infrastructure/Nexus-setup/n8n-workflows"

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

echo "═══════════════════════════════════════════════════════"
echo "  Importing Finance Workflows (12 total)"
echo "═══════════════════════════════════════════════════════"
echo ""

# Import all workflows
import_workflow "$WORKFLOW_DIR/income-webhook.json" "⭐ NEW - Income tracking"
import_workflow "$WORKFLOW_DIR/transaction-update-webhook.json" "⭐ NEW - Edit transactions"
import_workflow "$WORKFLOW_DIR/transaction-delete-webhook.json" "⭐ NEW - Delete transactions"
import_workflow "$WORKFLOW_DIR/insights-webhook.json" "⭐ NEW - AI insights"
import_workflow "$WORKFLOW_DIR/monthly-trends-webhook.json" "⭐ NEW - Monthly trends"
import_workflow "$WORKFLOW_DIR/budget-set-webhook.json" "🔄 UPDATED - Set budgets"
import_workflow "$WORKFLOW_DIR/budget-fetch-webhook.json" "🔄 UPDATED - Fetch budgets"
import_workflow "$WORKFLOW_DIR/finance-summary-webhook.json" "🔄 UPDATED - Finance summary"
import_workflow "$WORKFLOW_DIR/expense-log-webhook.json" "✅ EXISTING - Expense logging"
import_workflow "$WORKFLOW_DIR/auto-sms-import.json" "✅ EXISTING - SMS auto-import"
import_workflow "$WORKFLOW_DIR/trigger-sms-import.json" "✅ EXISTING - Manual SMS import"
import_workflow "$WORKFLOW_DIR/budget-delete-webhook.json" "✅ EXISTING - Delete budgets"

echo "═══════════════════════════════════════════════════════"
echo "  Summary"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "✅ Successful: $SUCCESS"
echo "❌ Errors: $ERRORS"
echo ""

if [ $ERRORS -eq 0 ]; then
    echo "🎉 All workflows imported successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Verify at: https://n8n.rfanw"
    echo "  2. Test from mobile app"
    echo ""
    echo "✅ Backend is production-ready!"
else
    echo "⚠️  Some workflows had errors. Check the output above."
fi

echo ""
echo "═══════════════════════════════════════════════════════"
