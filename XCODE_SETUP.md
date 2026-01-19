# Xcode Project Setup Guide

This guide walks through creating the Xcode project for Nexus from the existing source files.

## Quick Start

The source files are already created in the `Nexus/` directory. You just need to create an Xcode project and add them.

## Step 1: Create New Xcode Project

1. **Open Xcode 15+**

2. **Create New Project**
   - File → New → Project (or Cmd+Shift+N)
   - Select iOS → App
   - Click Next

3. **Configure Project**
   - **Product Name**: `Nexus`
   - **Team**: Select your Apple Developer team
   - **Organization Identifier**: `com.yourdomain` (replace with your actual domain)
   - **Bundle Identifier**: Will auto-populate as `com.yourdomain.Nexus`
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Storage**: None (we'll use UserDefaults/App Groups)
   - **Include Tests**: ☑️ (optional)
   - Click Next

4. **Save Location**
   - Navigate to `/Users/rafa/Cyber/Dev/Nexus-mobile`
   - **IMPORTANT**: Uncheck "Create Git repository" (already exists)
   - Click Create

5. **Clean Up Default Files**
   - Delete `ContentView.swift` (we have our own)
   - Delete `NexusApp.swift` (we have our own)
   - Keep `Assets.xcassets`
   - Keep `Preview Content` folder

## Step 2: Add Source Files

### Option A: Drag and Drop (Recommended)

1. **In Finder**
   - Open `/Users/rafa/Cyber/Dev/Nexus-mobile/Nexus` folder

2. **In Xcode Project Navigator**
   - Right-click on "Nexus" folder (blue icon)
   - Select "Add Files to Nexus..."

3. **Add All Directories**
   - Select and add each folder:
     - `Models/`
     - `Services/`
     - `ViewModels/`
     - `Views/`
     - `Widgets/`
   - Add individual files:
     - `NexusApp.swift`
     - `Info.plist`

4. **Configuration**
   - ☑️ Copy items if needed
   - ☑️ Create groups
   - Add to targets: Nexus
   - Click Add

### Option B: Link Existing Files

If files are already in the correct location:

1. Right-click Nexus folder in Xcode
2. Add Files to Nexus...
3. Navigate to existing files
4. **UNCHECK** "Copy items if needed"
5. Select "Create groups"
6. Add to Nexus target

## Step 3: Configure Info.plist

The `Info.plist` file should already be configured, but verify:

1. **Select Info.plist**
2. **Verify Keys**:
   - `NSSpeechRecognitionUsageDescription`
   - `NSMicrophoneUsageDescription`
   - `CFBundleDisplayName`: Nexus

3. **Update Build Settings**
   - Select Nexus project → Nexus target
   - Build Settings tab
   - Search for "Info.plist File"
   - Set to: `Nexus/Info.plist`

## Step 4: Configure App Settings

### Deployment Target

1. Select Nexus project
2. Select Nexus target
3. General tab
4. **Minimum Deployments**: iOS 17.0
   - (Or 16.0 if removing iOS 17-specific features)

### Signing & Capabilities

1. Go to "Signing & Capabilities" tab
2. **Automatically manage signing**: ☑️
3. **Team**: Select your team
4. **Bundle Identifier**: Verify it's correct

### Required Capabilities

Add these capabilities (click "+ Capability"):

1. **App Groups**
   - Click "+"
   - Add: `group.com.yourdomain.nexus`
   - Replace `yourdomain` with your bundle ID prefix

2. **Siri**
   - Just add the capability, no extra config needed

## Step 5: Update Bundle Identifiers in Code

### SharedStorage.swift

1. Open `Services/SharedStorage.swift`
2. Find line:
   ```swift
   private let appGroupID = "group.com.yourdomain.nexus"
   ```
3. Replace `yourdomain` with your actual bundle ID prefix
4. Must match the App Group you created

### Example

If your bundle ID is `com.example.Nexus`:
- App Group: `group.com.example.nexus`
- Update SharedStorage: `group.com.example.nexus`

## Step 6: Fix Build Issues

### Import Statements

All files should already have correct imports. Verify:

```swift
import SwiftUI
import Speech  // In FoodLogView, SpeechRecognizer
import AVFoundation  // In SpeechRecognizer
import WidgetKit  // In Widget files
import AppIntents  // In WidgetIntents
```

### Framework Linking

Xcode should auto-link frameworks, but verify in:
- Build Phases → Link Binary With Libraries
- Should include: SwiftUI, Speech, AVFoundation, WidgetKit

## Step 7: Build and Run

1. **Select Simulator**
   - iPhone 15 Pro or newer
   - iOS 17.0+

2. **Build**
   - Product → Build (Cmd+B)
   - Fix any errors (should be none if steps followed)

3. **Run**
   - Product → Run (Cmd+R)
   - App should launch successfully

4. **Test Basic Functionality**
   - Navigate to Settings
   - Enter webhook URL: `https://n8n.rfanw`
   - Save settings
   - Go to Quick Log
   - Try typing and logging

## Step 8: Configure Webhook URL

**In Settings View:**

1. Launch app
2. Tap Settings tab
3. Enter your n8n webhook base URL
   - Example: `https://n8n.rfanw`
   - Without trailing slash
   - Without `/webhook/` path
4. Tap "Save Settings"
5. Tap "Test Connection" to verify

## Step 9: Test Voice Input

1. **Grant Permissions**
   - Launch app
   - Go to Food or Quick Log tab
   - Tap microphone icon
   - Grant Speech Recognition permission
   - Grant Microphone permission

2. **Test Recording**
   - Tap mic icon (should turn red)
   - Speak: "2 eggs for breakfast"
   - Tap mic icon again to stop
   - Text should appear in input field

## Step 10: Add Widget Extension (Optional)

See `WIDGET_SETUP.md` for detailed widget configuration.

**Quick Steps:**

1. File → New → Target
2. Widget Extension
3. Name: `NexusWidgets`
4. Add widget files to target
5. Configure App Groups
6. Build and test

## Common Build Errors

### "Cannot find type 'NexusAPI' in scope"

**Fix**: Ensure `Services/NexusAPI.swift` is added to target
- Select file
- File Inspector → Target Membership
- Check "Nexus"

### "Missing Info.plist"

**Fix**:
- Build Settings → "Info.plist File"
- Set to: `Nexus/Info.plist`

### "Signing requires a development team"

**Fix**:
- Select Nexus target
- Signing & Capabilities
- Select your team
- May need to log in to Apple ID in Xcode Preferences

### "Sandbox: rsync deny file-read-data"

**Fix**: This is normal during build, can be ignored

## Project Structure Verification

Your Xcode project should look like:

```
Nexus (project)
└── Nexus (group)
    ├── NexusApp.swift
    ├── Models/
    │   └── NexusModels.swift
    ├── Services/
    │   ├── NexusAPI.swift
    │   ├── SpeechRecognizer.swift
    │   └── SharedStorage.swift
    ├── ViewModels/
    │   └── DashboardViewModel.swift
    ├── Views/
    │   ├── ContentView.swift
    │   ├── Dashboard/
    │   │   └── DashboardView.swift
    │   ├── QuickLogView.swift
    │   ├── Food/
    │   │   └── FoodLogView.swift
    │   └── SettingsView.swift
    ├── Widgets/
    │   ├── NexusWidgets.swift
    │   ├── InteractiveWaterWidget.swift
    │   └── WidgetIntents.swift
    ├── Assets.xcassets
    ├── Preview Content/
    └── Info.plist
```

## Testing Checklist

After setup, verify:

- [ ] App builds successfully (Cmd+B)
- [ ] App runs in simulator (Cmd+R)
- [ ] All tabs are accessible (Dashboard, Quick Log, Food, Settings)
- [ ] Settings can be saved
- [ ] Webhook URL can be configured
- [ ] Voice input button appears
- [ ] No compiler warnings (ideally)

## Next Steps

1. **Configure Backend**
   - Ensure n8n is running
   - Configure webhook URL in app
   - Test connection

2. **Test Logging**
   - Try Quick Log
   - Try Food logging
   - Verify data appears on backend

3. **Add Widgets**
   - Follow `WIDGET_SETUP.md`
   - Configure App Groups
   - Test widget functionality

4. **Deploy to Device**
   - Connect iPhone via USB
   - Select device in Xcode
   - Build and run
   - Grant permissions
   - Test on real hardware

## Troubleshooting

### App crashes on launch

- Check Console logs (Cmd+Shift+Y)
- Verify all files are added to target
- Check for syntax errors in swift files

### Settings not persisting

- Check `AppSettings` class in `NexusApp.swift`
- Verify `@AppStorage` is working
- Clear simulator (Device → Erase All Content and Settings)

### API calls fail

- Verify webhook URL is correct
- Check n8n is running and accessible
- Use Test Connection in Settings
- Check Console logs for error details

## Resources

- Main README: `README.md`
- Widget Setup: `WIDGET_SETUP.md`
- n8n Workflows: `/Users/rafa/Cyber/Infrastructure/Nexus-setup/`
