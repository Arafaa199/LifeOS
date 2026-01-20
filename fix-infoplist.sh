#!/bin/bash

echo "🔧 Fixing Info.plist build issue..."
echo ""

cd /Users/rafa/Cyber/Dev/Nexus-mobile

# Clean build folder
echo "1. Cleaning build folder..."
rm -rf ~/Library/Developer/Xcode/DerivedData/Nexus-*

echo "✅ Build folder cleaned"
echo ""

echo "2. Next steps in Xcode:"
echo "   a. Open Nexus.xcodeproj"
echo "   b. Select Nexus target → Build Phases"
echo "   c. Expand 'Copy Bundle Resources'"
echo "   d. Remove Info.plist if it's there (click '-' button)"
echo "   e. Product → Clean Build Folder (Cmd+Shift+K)"
echo "   f. Build again (Cmd+B)"
echo ""
echo "✅ Should build successfully!"
