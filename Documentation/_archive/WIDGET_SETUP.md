# Nexus Widget Setup Guide

This guide explains how to configure the Nexus iOS widgets in Xcode.

## Prerequisites

- Xcode 15+
- iOS 17+ deployment target (for interactive widgets and App Intents)
- Apple Developer account (for App Groups capability)

## Step 1: Create Widget Extension

1. **Add Widget Extension Target**
   - In Xcode, go to File → New → Target
   - Select "Widget Extension"
   - Product Name: `NexusWidgets`
   - Uncheck "Include Configuration Intent"
   - Click Finish
   - When prompted, activate the scheme

2. **Delete Default Files**
   - Delete the auto-generated `NexusWidgets.swift` file
   - Delete `Assets.xcassets` in the widget target (we'll use the app's assets)

3. **Add Widget Files to Target**
   - Select `Nexus/Widgets/NexusWidgets.swift`
   - In File Inspector (right panel), check both targets:
     - [x] Nexus
     - [x] NexusWidgets
   - Repeat for:
     - `InteractiveWaterWidget.swift`
     - `WidgetIntents.swift`

4. **Add Shared Files to Widget Target**
   - Select these files and add to NexusWidgets target:
     - `Services/NexusAPI.swift`
     - `Services/SharedStorage.swift`
     - `Models/NexusModels.swift`

## Step 2: Configure App Groups

App Groups allow the main app and widgets to share data.

### Create App Group

1. **In App Target (Nexus)**
   - Select Nexus project → Nexus target
   - Go to "Signing & Capabilities" tab
   - Click "+ Capability"
   - Add "App Groups"
   - Click "+" under App Groups
   - Enter: `group.com.yourdomain.nexus`
   - Replace `yourdomain` with your actual bundle identifier prefix

2. **In Widget Target (NexusWidgets)**
   - Select NexusWidgets target
   - Go to "Signing & Capabilities" tab
   - Add "App Groups" capability
   - Select the same group: `group.com.yourdomain.nexus`

### Update Shared Storage

3. **Configure App Group ID**
   - Open `Services/SharedStorage.swift`
   - Update the `appGroupID` to match your group:
   ```swift
   private let appGroupID = "group.com.yourdomain.nexus"
   ```

## Step 3: Add Siri & App Intents Capability

For Siri shortcuts and App Intents to work:

1. **App Target**
   - Signing & Capabilities → "+ Capability"
   - Add "Siri"

2. **Info.plist Configuration**
   - Open `Info.plist`
   - Add key: `NSUserActivityTypes` (Array)
   - The app intents are auto-registered via `NexusAppShortcuts`

## Step 4: Update Widget Bundle in NexusWidgets.swift

Make sure the widget bundle includes all widgets:

```swift
@main
struct NexusWidgets: WidgetBundle {
    var body: some Widget {
        WaterQuickLogWidget()
        DailySummaryWidget()
        if #available(iOS 17.0, *) {
            InteractiveWaterWidget()
        }
    }
}
```

## Step 5: Configure Build Settings

1. **Deployment Target**
   - Set both Nexus and NexusWidgets targets to iOS 17.0+
   - (Or iOS 16.0+ if you remove iOS 17-specific features)

2. **Bundle Identifier**
   - Main app: `com.yourdomain.nexus`
   - Widget: `com.yourdomain.nexus.NexusWidgets`

## Step 6: Test Widgets

### In Simulator

1. Run the app in Simulator (Cmd+R)
2. Stop the app
3. Long press on Home Screen
4. Tap "+" in top left corner
5. Search for "Nexus"
6. Add widgets to Home Screen

### Testing Interactive Buttons

1. Add the "Interactive Water Widget" (medium size)
2. Tap the 250ml/500ml/1L buttons
3. Check Console logs for API calls
4. Verify data updates in the main app

### Testing App Intents

1. Open Shortcuts app
2. Create new shortcut
3. Add "Run App Intent"
4. Select Nexus → Log Water
5. Configure amount (250ml)
6. Run shortcut and verify

## Step 7: Test Siri Integration

1. **Enable Siri Shortcuts**
   - Settings → Siri & Search → Nexus
   - Enable "Learn from this App"
   - Enable "Show in Search"
   - Enable "Show in Spotlight"

2. **Test Siri Commands**
   - "Hey Siri, log water in Nexus"
   - "Hey Siri, log to Nexus 2 eggs for breakfast"

## Common Issues

### Widget Not Appearing

**Issue**: Widget doesn't show in widget gallery

**Fix**:
- Ensure widget target is added to the scheme
- Clean build folder (Cmd+Shift+K)
- Delete app from simulator
- Rebuild and run

### Shared Data Not Updating

**Issue**: Widget shows 0 even after logging in app

**Fix**:
- Verify App Group ID matches in both targets
- Check `SharedStorage.swift` uses correct group ID
- Ensure widget files are added to widget target
- Update `DashboardViewModel` to save to SharedStorage:

```swift
func updateSummaryAfterLog(type: LogType, response: NexusResponse) {
    // ... existing code ...

    // Save to shared storage for widgets
    SharedStorage.shared.saveDailySummary(
        calories: summary.totalCalories,
        protein: summary.totalProtein,
        water: summary.totalWater,
        weight: summary.weight
    )
}
```

### App Intents Not Working

**Issue**: Siri says "I can't help with that"

**Fix**:
- Ensure Siri capability is added
- Check `NexusAppShortcuts` is properly declared
- Rebuild app and wait a few minutes for Siri to index
- Try disabling and re-enabling Siri for the app

### Build Errors with @available

**Issue**: "'InteractiveWaterWidget' is only available in iOS 17.0 or newer"

**Fix**:
- Wrap iOS 17+ widgets in availability checks:
```swift
if #available(iOS 17.0, *) {
    InteractiveWaterWidget()
}
```

## Testing Checklist

- [ ] App builds and runs successfully
- [ ] Widget extension builds successfully
- [ ] Widgets appear in widget gallery
- [ ] Small water widget displays correctly
- [ ] Medium water widget displays correctly
- [ ] Medium summary widget displays correctly
- [ ] Large summary widget displays correctly
- [ ] Interactive buttons log water (iOS 17+)
- [ ] Data updates between app and widgets
- [ ] Siri shortcuts work
- [ ] App intents execute correctly
- [ ] Daily stats reset at midnight

## Production Deployment

Before shipping to TestFlight/App Store:

1. **Update App Group ID**
   - Use your production bundle identifier
   - Update in both targets
   - Update `SharedStorage.swift`

2. **Configure Provisioning Profiles**
   - Include App Groups entitlement
   - Include Siri entitlement

3. **Test on Physical Device**
   - Widgets behave differently on device vs simulator
   - Test all widget sizes
   - Test interactive buttons
   - Test Siri integration

4. **Update App Store Connect**
   - Enable Siri capability in App Store Connect
   - Add widget screenshots to listing

## Resources

- [Apple Widgets Documentation](https://developer.apple.com/documentation/widgetkit)
- [App Intents Documentation](https://developer.apple.com/documentation/appintents)
- [App Groups Guide](https://developer.apple.com/documentation/xcode/configuring-app-groups)
