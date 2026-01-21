# 📱 Enable Widgets - Step by Step

## Current Status

✅ App builds and runs
❌ Widgets not functional (need Widget Extension target)

---

## 🎯 Create Widget Extension

### Step 1: Create Widget Extension Target

**In Xcode:**

1. **File → New → Target**
2. Choose **Widget Extension**
3. Set name: **NexusWidgets**
4. **Important:** Uncheck "Include Configuration Intent"
5. Click **Finish**
6. If asked to activate scheme, click **Activate**

---

### Step 2: Delete Generated Files

Xcode creates sample files we don't need:

**Delete these files:**
- `NexusWidgets/NexusWidgets.swift` (the generated one)
- `NexusWidgets/Assets.xcassets` (we'll share the main one)

---

### Step 3: Move Widget Files to Extension

**Move these 3 files to the NexusWidgets target:**

1. `Nexus/Widgets/NexusWidgets.swift`
2. `Nexus/Widgets/WidgetIntents.swift`
3. `Nexus/Widgets/InteractiveWaterWidget.swift`

**How to move:**
- Right-click each file → **Show File Inspector** (⌥⌘1)
- Under "Target Membership", **uncheck** Nexus
- **Check** NexusWidgets

---

### Step 4: Share Code Between Targets

**Add these files to BOTH targets (Nexus + NexusWidgets):**

1. `Services/SharedStorage.swift`
2. `Services/NexusAPI.swift`
3. `Models/NexusModels.swift`
4. `Services/NetworkMonitor.swift`

**How:**
- Right-click each file → **Show File Inspector**
- Under "Target Membership", **check both:**
  - ✅ Nexus
  - ✅ NexusWidgets

---

### Step 5: Uncomment @main in Widget Bundle

**Edit `NexusWidgets.swift`:**

Find this:
```swift
// @main - Commented out to avoid conflict with NexusApp.swift
// Uncomment this when widgets are in their own extension target
struct NexusWidgets: WidgetBundle {
```

Change to:
```swift
@main
struct NexusWidgets: WidgetBundle {
```

---

### Step 6: Configure App Groups

Widgets and the app need to share data via App Groups.

**In Xcode:**

1. **Select Nexus target** → Signing & Capabilities
2. Click **+ Capability**
3. Add **App Groups**
4. Click **+** and create: `group.com.yourdomain.nexus`
   - Replace `yourdomain` with your actual domain or bundle ID prefix

5. **Select NexusWidgets target** → Signing & Capabilities
6. Add **App Groups** (same as above)
7. Check the **same** `group.com.yourdomain.nexus`

**Update SharedStorage.swift:**

Change line 3 to match your App Group ID:
```swift
private let appGroupID = "group.com.yourdomain.nexus"
```

---

### Step 7: Build & Run

1. **Clean:** Cmd+Shift+K
2. **Build:** Cmd+B
3. **Run:** Cmd+R

---

### Step 8: Add Widget to Home Screen

**In Simulator:**

1. Press **Cmd+Shift+H** (go to home screen)
2. **Long press** on empty space
3. Tap **+** button (top left)
4. Search for **"Nexus"**
5. Choose widget:
   - **Water Quick Log** (small)
   - **Daily Summary** (medium/large)
6. Tap **Add Widget**

---

## ✅ Verification

Widget should show:
- Water today (ml)
- Calories, protein, water, weight (summary widget)
- Tap to log water

**Test:**
1. Log water in the app
2. Widget should update automatically
3. Tap widget → should log 250ml water

---

## 🎯 Interactive Widgets (iOS 17+)

The `InteractiveWaterWidget.swift` has **buttons** for quick logging:
- 250ml button
- 500ml button
- 1000ml button

This requires iOS 17+ simulator.

---

## 📝 Troubleshooting

### Widget Shows "No Data"
- Check App Group ID matches in both targets
- Verify SharedStorage.swift uses correct App Group ID
- Log something in the app first

### Widget Not Appearing
- Make sure NexusWidgets target builds successfully
- Check widget is added to home screen correctly
- Try deleting and re-adding widget

### Data Not Syncing
- Verify App Groups capability on both targets
- Check `WidgetCenter.shared.reloadAllTimelines()` is called
- Look for errors in Xcode console

---

*Widgets will be fully functional after completing these steps!*
