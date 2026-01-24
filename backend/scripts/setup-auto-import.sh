#!/bin/bash

# Quick Setup Script for SMS Auto-Import
# Run this once to set up automatic transaction import from Messages app

set -e

echo "🚀 Nexus SMS Auto-Import Setup"
echo "================================"
echo ""

# Check if on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ This script must run on macOS (where Messages app is)"
    exit 1
fi

# Check Messages database exists
if [ ! -f "$HOME/Library/Messages/chat.db" ]; then
    echo "❌ Messages database not found"
    echo "   Make sure Messages app is set up and synced"
    exit 1
fi

echo "✅ Messages database found"

# Get Nexus password
read -sp "Enter Nexus database password: " NEXUS_PASSWORD
echo ""

if [ -z "$NEXUS_PASSWORD" ]; then
    echo "❌ Password required"
    exit 1
fi

# Test database connection
export NEXUS_PASSWORD
echo "Testing database connection..."

if ! PGPASSWORD=$NEXUS_PASSWORD psql -h 100.90.189.16 -U nexus -d nexus -c "SELECT 1" > /dev/null 2>&1; then
    echo "❌ Cannot connect to Nexus database"
    echo "   Check network and credentials"
    exit 1
fi

echo "✅ Database connection successful"

# Install dependencies if needed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js not found. Install from https://nodejs.org"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -d "node_modules" ]; then
    echo "Installing dependencies..."
    npm install better-sqlite3 pg
fi

echo "✅ Dependencies ready"

# Test import (last 7 days)
echo ""
echo "Running test import (last 7 days)..."
node import-sms-transactions.js 7

echo ""
echo "✅ Test import completed!"
echo ""

# Create launchd job
echo "Setting up automatic import (every 15 minutes)..."

PLIST_FILE="$HOME/Library/LaunchAgents/com.nexus.sms-import.plist"

cat > "$PLIST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.nexus.sms-import</string>

    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_DIR/auto-import-sms.sh</string>
        <string>1</string>
    </array>

    <key>StartInterval</key>
    <integer>900</integer>

    <key>EnvironmentVariables</key>
    <dict>
        <key>NEXUS_PASSWORD</key>
        <string>$NEXUS_PASSWORD</string>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin</string>
    </dict>

    <key>StandardOutPath</key>
    <string>/tmp/nexus-sms-import.log</string>

    <key>StandardErrorPath</key>
    <string>/tmp/nexus-sms-import-error.log</string>

    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF

# Load the job
launchctl unload "$PLIST_FILE" 2>/dev/null || true
launchctl load "$PLIST_FILE"

echo "✅ Automatic import configured!"
echo ""
echo "================================"
echo "✅ Setup Complete!"
echo "================================"
echo ""
echo "What happens now:"
echo "  • SMS transactions import every 15 minutes"
echo "  • Check logs: tail -f /tmp/nexus-sms-import.log"
echo "  • View transactions in iOS app Finance tab"
echo ""
echo "Commands:"
echo "  • Manual import: cd $SCRIPT_DIR && node import-sms-transactions.js 7"
echo "  • Stop auto-import: launchctl unload $PLIST_FILE"
echo "  • Start auto-import: launchctl load $PLIST_FILE"
echo ""
echo "🎉 All done! Open the Nexus app and check the Finance tab!"
