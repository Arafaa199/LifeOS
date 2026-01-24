#!/bin/bash
# Quick fix for NocoDB database connection issue
# Run this on the nexus server

set -e

echo "🔧 Nexus NocoDB Connection Fix"
echo "================================"
echo ""

# Find docker-compose.yml
COMPOSE_FILE=""
for location in ~/docker-compose.yml ~/nexus-setup/docker-compose.yml /opt/nexus/docker-compose.yml; do
    if [ -f "$location" ]; then
        COMPOSE_FILE="$location"
        break
    fi
done

if [ -z "$COMPOSE_FILE" ]; then
    echo "❌ Error: Could not find docker-compose.yml"
    echo "Please locate your docker-compose.yml and run:"
    echo "  sed -i 's|pg://postgres:5432|pg://nexus-db:5432|g' /path/to/docker-compose.yml"
    echo "  docker compose restart nocodb"
    exit 1
fi

echo "📁 Found docker-compose.yml at: $COMPOSE_FILE"
echo ""

# Backup
echo "💾 Creating backup..."
cp "$COMPOSE_FILE" "${COMPOSE_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
echo "✅ Backup created"
echo ""

# Check if fix is needed
if grep -q "pg://postgres:5432" "$COMPOSE_FILE"; then
    echo "🔍 Found issue: NC_DB uses 'postgres' instead of 'nexus-db'"
    echo "📝 Applying fix..."

    # Apply fix
    sed -i.tmp 's|pg://postgres:5432|pg://nexus-db:5432|g' "$COMPOSE_FILE"
    rm -f "${COMPOSE_FILE}.tmp"

    echo "✅ Fix applied"
    echo ""

    # Restart NocoDB
    echo "🔄 Restarting NocoDB container..."
    cd "$(dirname "$COMPOSE_FILE")"
    docker compose restart nocodb

    echo ""
    echo "⏳ Waiting for NocoDB to start (10 seconds)..."
    sleep 10

    # Check logs
    echo ""
    echo "📋 Recent logs:"
    docker logs nexus-ui --tail 20

    echo ""
    echo "✅ Fix complete!"
    echo ""
    echo "🌐 NocoDB should now be accessible at:"
    echo "   http://localhost:8080"
    echo ""
    echo "If you still see errors, check the logs with:"
    echo "   docker logs nexus-ui -f"

else
    echo "✅ Connection string already correct (pg://nexus-db:5432)"
    echo "No changes needed."
    echo ""
    echo "If NocoDB still has issues, check logs:"
    echo "   docker logs nexus-ui -f"
fi

echo ""
echo "Done! 🎉"
