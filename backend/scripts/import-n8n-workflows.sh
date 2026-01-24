#!/bin/bash
# Import all n8n workflows via API
# Usage: ./import-n8n-workflows.sh [API_KEY]

set -e

N8N_URL="https://n8n.rfanw"
WORKFLOW_DIR="/Users/rafa/Cyber/Infrastructure/Nexus-setup/n8n-workflows"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     n8n Workflow Import Script                      ║${NC}"
echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo ""

# Get API key
if [ -z "$1" ]; then
    echo -e "${YELLOW}⚠️  n8n API Key Required${NC}"
    echo ""
    echo "To get your API key:"
    echo "  1. Open https://n8n.rfanw in your browser"
    echo "  2. Go to Settings → API"
    echo "  3. Click 'Create API Key'"
    echo "  4. Copy the key"
    echo ""
    read -sp "Enter your n8n API Key: " API_KEY
    echo ""
else
    API_KEY="$1"
fi

if [ -z "$API_KEY" ]; then
    echo -e "${RED}❌ No API key provided. Exiting.${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}🔍 Testing API connection...${NC}"

# Test API connection
RESPONSE=$(curl -s -w "\n%{http_code}" -H "X-N8N-API-KEY: $API_KEY" "$N8N_URL/api/v1/workflows")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "200" ]; then
    echo -e "${RED}❌ API connection failed (HTTP $HTTP_CODE)${NC}"
    echo "Response: $BODY"
    exit 1
fi

echo -e "${GREEN}✅ API connection successful${NC}"
echo ""

# Get existing workflows
echo -e "${BLUE}📋 Fetching existing workflows...${NC}"
EXISTING_WORKFLOWS=$(echo "$BODY" | jq -r '.data[]? | "\(.name)|\(.id)"' 2>/dev/null || echo "")
echo -e "${GREEN}✅ Found $(echo "$EXISTING_WORKFLOWS" | grep -c . || echo 0) existing workflows${NC}"
echo ""

# Finance workflows that need to be imported
declare -A FINANCE_WORKFLOWS=(
    ["income-webhook.json"]="⭐ NEW - Income tracking"
    ["transaction-update-webhook.json"]="⭐ NEW - Edit transactions"
    ["transaction-delete-webhook.json"]="⭐ NEW - Delete transactions"
    ["insights-webhook.json"]="⭐ NEW - AI insights"
    ["monthly-trends-webhook.json"]="⭐ NEW - Monthly trends"
    ["budget-set-webhook.json"]="🔄 UPDATED - Set budgets (fixed dates)"
    ["budget-fetch-webhook.json"]="🔄 UPDATED - Fetch budgets (fixed dates)"
    ["finance-summary-webhook.json"]="🔄 UPDATED - Finance summary (added budgets)"
    ["expense-log-webhook.json"]="✅ EXISTING - Quick expense logging"
    ["auto-sms-import.json"]="✅ EXISTING - SMS auto-import"
    ["trigger-sms-import.json"]="✅ EXISTING - Manual SMS import"
    ["budget-delete-webhook.json"]="✅ EXISTING - Delete budgets"
)

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Importing Finance Workflows (12 total)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

SUCCESS_COUNT=0
SKIP_COUNT=0
ERROR_COUNT=0

for workflow_file in "${!FINANCE_WORKFLOWS[@]}"; do
    workflow_path="$WORKFLOW_DIR/$workflow_file"
    description="${FINANCE_WORKFLOWS[$workflow_file]}"

    if [ ! -f "$workflow_path" ]; then
        echo -e "${RED}❌ File not found: $workflow_file${NC}"
        ((ERROR_COUNT++))
        continue
    fi

    # Get workflow name from file
    WORKFLOW_NAME=$(jq -r '.name' "$workflow_path")

    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📦 Processing: ${WORKFLOW_NAME}${NC}"
    echo -e "   ${description}"
    echo ""

    # Check if workflow already exists
    EXISTING_ID=$(echo "$EXISTING_WORKFLOWS" | grep "^${WORKFLOW_NAME}|" | cut -d'|' -f2 || echo "")

    if [ -n "$EXISTING_ID" ]; then
        echo -e "${YELLOW}⚠️  Workflow already exists (ID: $EXISTING_ID)${NC}"
        read -p "   Update it? (y/N): " -n 1 -r
        echo ""

        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}⏭️  Skipped${NC}"
            ((SKIP_COUNT++))
            continue
        fi

        # Update existing workflow
        echo -e "${BLUE}🔄 Updating workflow...${NC}"
        UPDATE_DATA=$(cat "$workflow_path")

        RESPONSE=$(curl -s -w "\n%{http_code}" \
            -X PUT \
            -H "X-N8N-API-KEY: $API_KEY" \
            -H "Content-Type: application/json" \
            -d "$UPDATE_DATA" \
            "$N8N_URL/api/v1/workflows/$EXISTING_ID")

        HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

        if [ "$HTTP_CODE" == "200" ]; then
            echo -e "${GREEN}✅ Updated successfully${NC}"

            # Activate workflow
            echo -e "${BLUE}🟢 Activating workflow...${NC}"
            ACTIVATE_RESPONSE=$(curl -s -w "\n%{http_code}" \
                -X PATCH \
                -H "X-N8N-API-KEY: $API_KEY" \
                -H "Content-Type: application/json" \
                -d '{"active": true}' \
                "$N8N_URL/api/v1/workflows/$EXISTING_ID")

            ACTIVATE_CODE=$(echo "$ACTIVATE_RESPONSE" | tail -n1)
            if [ "$ACTIVATE_CODE" == "200" ]; then
                echo -e "${GREEN}✅ Activated${NC}"
            else
                echo -e "${YELLOW}⚠️  Could not activate (code: $ACTIVATE_CODE)${NC}"
            fi

            ((SUCCESS_COUNT++))
        else
            echo -e "${RED}❌ Update failed (HTTP $HTTP_CODE)${NC}"
            echo "   Response: $(echo "$RESPONSE" | sed '$d')"
            ((ERROR_COUNT++))
        fi
    else
        # Create new workflow
        echo -e "${BLUE}➕ Creating new workflow...${NC}"
        WORKFLOW_DATA=$(cat "$workflow_path")

        RESPONSE=$(curl -s -w "\n%{http_code}" \
            -X POST \
            -H "X-N8N-API-KEY: $API_KEY" \
            -H "Content-Type: application/json" \
            -d "$WORKFLOW_DATA" \
            "$N8N_URL/api/v1/workflows")

        HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
        BODY=$(echo "$RESPONSE" | sed '$d')

        if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "201" ]; then
            NEW_ID=$(echo "$BODY" | jq -r '.data.id' 2>/dev/null || echo "")
            echo -e "${GREEN}✅ Created successfully (ID: $NEW_ID)${NC}"

            # Activate workflow
            if [ -n "$NEW_ID" ]; then
                echo -e "${BLUE}🟢 Activating workflow...${NC}"
                ACTIVATE_RESPONSE=$(curl -s -w "\n%{http_code}" \
                    -X PATCH \
                    -H "X-N8N-API-KEY: $API_KEY" \
                    -H "Content-Type: application/json" \
                    -d '{"active": true}' \
                    "$N8N_URL/api/v1/workflows/$NEW_ID")

                ACTIVATE_CODE=$(echo "$ACTIVATE_RESPONSE" | tail -n1)
                if [ "$ACTIVATE_CODE" == "200" ]; then
                    echo -e "${GREEN}✅ Activated${NC}"
                else
                    echo -e "${YELLOW}⚠️  Could not activate (code: $ACTIVATE_CODE)${NC}"
                fi
            fi

            ((SUCCESS_COUNT++))
        else
            echo -e "${RED}❌ Creation failed (HTTP $HTTP_CODE)${NC}"
            echo "   Response: $BODY"
            ((ERROR_COUNT++))
        fi
    fi

    echo ""
done

# Summary
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Import Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}✅ Successful: $SUCCESS_COUNT${NC}"
echo -e "${BLUE}⏭️  Skipped: $SKIP_COUNT${NC}"
echo -e "${RED}❌ Errors: $ERROR_COUNT${NC}"
echo ""

if [ $ERROR_COUNT -eq 0 ]; then
    echo -e "${GREEN}🎉 All workflows imported successfully!${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. Verify workflows at: https://n8n.rfanw"
    echo "  2. Check that all 12 workflows are activated (green toggle)"
    echo "  3. Test webhooks from your mobile app"
    echo ""
    echo -e "${GREEN}✅ Your backend is now production-ready!${NC}"
else
    echo -e "${YELLOW}⚠️  Some workflows had errors. Please check the output above.${NC}"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
