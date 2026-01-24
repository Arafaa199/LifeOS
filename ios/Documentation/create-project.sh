#!/bin/bash

# Nexus iOS App - Create Xcode Project Script
# This creates a proper Xcode project structure

cd "/Users/rafa/Cyber/Dev/Nexus-mobile"

echo "🚀 Creating Nexus Xcode Project..."
echo ""

# Check if Xcode command line tools are installed
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode command line tools not found."
    echo "Please install Xcode first, then run: xcode-select --install"
    exit 1
fi

# Check if project already exists
if [ -f "Nexus.xcodeproj/project.pbxproj" ]; then
    echo "⚠️  Nexus.xcodeproj already exists!"
    read -p "Delete and recreate? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf Nexus.xcodeproj
        echo "✓ Removed old project"
    else
        echo "Cancelled."
        exit 0
    fi
fi

echo "📦 Creating Xcode project..."

# Create the Xcode project using xcodebuild (or tell user to use Xcode GUI)
cat << 'EOF'

⚠️  MANUAL STEP REQUIRED

Unfortunately, creating an Xcode project from scratch requires Xcode GUI.

Please follow these steps:

1. Open Xcode

2. File → New → Project (Cmd+Shift+N)

3. Select: iOS → App

4. Configure:
   - Product Name: Nexus
   - Team: (select your team)
   - Organization Identifier: com.yourdomain
   - Interface: SwiftUI
   - Language: Swift
   - Storage: None
   - Include Tests: No (we'll add later if needed)

5. Save Location: /Users/rafa/Cyber/Dev/Nexus-mobile

   ⚠️  IMPORTANT: UNCHECK "Create Git repository"

6. Click "Create"

7. Xcode will create:
   ├── Nexus.xcodeproj
   └── Nexus/
       ├── NexusApp.swift  (auto-generated - DELETE THIS)
       ├── ContentView.swift  (auto-generated - DELETE THIS)
       └── Assets.xcassets

8. DELETE the auto-generated files:
   - Right-click Nexus/NexusApp.swift → Delete (Move to Trash)
   - Right-click Nexus/ContentView.swift → Delete (Move to Trash)

9. Our source files are already in Nexus/ folder, so:
   - They should automatically appear in Xcode
   - If not: Right-click "Nexus" folder → Add Files to "Nexus"
     → Select all folders (Models, Services, Views, etc.)

10. Configure capabilities:
    - Select Nexus target
    - Signing & Capabilities tab
    - Add: App Groups (group.com.yourdomain.nexus)
    - Add: Siri

11. Update SharedStorage.swift:
    - Change: group.com.yourdomain.nexus
    - To match your bundle identifier

12. Build & Run! (Cmd+R)

EOF

echo "📄 After Xcode project is created, your structure will be:"
echo ""
echo "/Nexus-mobile/"
echo "├── Nexus.xcodeproj       ← Xcode project file"
echo "└── Nexus/                ← Source code"
echo "    ├── NexusApp.swift"
echo "    ├── Models/"
echo "    ├── Services/"
echo "    ├── ViewModels/"
echo "    ├── Views/"
echo "    └── Widgets/"
echo ""
echo "✅ Clean structure - ready to build!"
