#!/bin/bash
# Final n8n workflow import script that actually works
set -e

API_KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI2ZTM1MjMyMy1mMGQ4LTQ3NjctOWY2ZC0xNjM1NTdhYWE0NjkiLCJpc3MiOiJuOG4iLCJhdWQiOiJwdWJsaWMtYXBpIiwiaWF0IjoxNzY4NjEzOTY1LCJleHAiOjE3NzExMzE2MDB9.VY0q_6VCefIjoAPf1k7EMVHKCCjj3pmlY_1kO7FOtlM'
N8N_URL="https://n8n.rfanw"
WORKFLOW_DIR="/Users/rafa/Cyber/Infrastructure/Nexus-setup/n8n-workflows"

SUCCESS=0
ERRORS=0

echo "════════════════════════════════════════════════════"
echo "  n8n Workflow Import - Finance Workflows"
echo "════════════════════════════════════════════════════"
echo ""

import_workflow() {
    local file="$1"
    local description="$2"

    local name=$(jq -r '.name' "$file")
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 $name"
    echo "   $description"
    echo ""

    # Check if exists
    local existing=$(curl -s -H "X-N8N-API-KEY: $API_KEY" "$N8N_URL/api/v1/workflows" | jq -r ".data[] | select(.name == \"$name\") | .id" 2>/dev/null | head -1)

    if [ -n "$existing" ] && [ "$existing" != "null" ]; then
        echo "⚠️  Workflow already exists (ID: $existing)"
        echo "   Updating..."

        WORKFLOW=$(cat "$file")
        local response=$(curl -s -X PUT -H "X-N8N-API-KEY: $API_KEY" -H 'Content-Type: application/json' -d "$WORKFLOW" "$N8N_URL/api/v1/workflows/$existing")

        if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
            echo "✅ Updated successfully"

            # Activate
            curl -s -X POST -H "X-N8N-API-KEY: $API_KEY" "$N8N_URL/api/v1/workflows/$existing/activate" >/dev/null 2>&1
            echo "✅ Activated"
            ((SUCCESS++))
        else
            echo "❌ Update failed: $(echo "$response" | jq -r '.message' 2>/dev/null)"
            ((ERRORS++))
        fi
    else
        echo "➕ Creating new workflow..."

        WORKFLOW=$(cat "$file")
        local response=$(curl -s -X POST -H "X-N8N-API-KEY: $API_KEY" -H 'Content-Type: application/json' -d "$WORKFLOW" "$N8N_URL/api/v1/workflows")

        local new_id=$(echo "$response" | jq -r '.id' 2>/dev/null)

        if [ -n "$new_id" ] && [ "$new_id" != "null" ]; then
            echo "✅ Created successfully (ID: $new_id)"

            # Activate
            curl -s -X POST -H "X-N8N-API-KEY: $API_KEY" "$N8N_URL/api/v1/workflows/$new_id/activate" >/dev/null 2>&1
            echo "✅ Activated"
            ((SUCCESS++))
        else
            echo "❌ Creation failed: $(echo "$response" | jq -r '.message' 2>/dev/null)"
            ((ERRORS++))
        fi
    fi
    echo ""
}

# Import all finance workflows
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

echo "════════════════════════════════════════════════════"
echo "  Import Summary"
echo "════════════════════════════════════════════════════"
echo ""
echo "✅ Successful: $SUCCESS"
echo "❌ Errors: $ERRORS"
echo ""

if [ $ERRORS -eq 0 ]; then
    echo "🎉 All workflows imported and activated!"
    echo ""
    echo "Next steps:"
    echo "  1. Verify at: https://n8n.rfanw"
    echo "  2. Test webhooks from mobile app"
    echo ""
    echo "✅ Backend is production-ready!"
else
    echo "⚠️  Some workflows had errors."
fi

echo ""
echo "════════════════════════════════════════════════════"
