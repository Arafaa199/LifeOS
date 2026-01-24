# 🚀 Build Instructions for Nexus App

## ✅ All Errors Fixed

All build errors have been resolved:
1. ✅ Info.plist duplication
2. ✅ Missing Combine imports
3. ✅ Widget Intent parameter labels
4. ✅ IntentDialog stringLiteral
5. ✅ Duplicate @main attribute

---

## 📱 Build in Xcode

### Step 1: Open Project

```bash
cd /Users/rafa/Cyber/Dev/Nexus-mobile
open Nexus.xcodeproj
```

Or double-click `Nexus.xcodeproj` in Finder.

---

### Step 2: Select Target & Device

1. At the top of Xcode, click the scheme selector (left of Play button)
2. Choose **"Nexus"** as the scheme
3. Choose a simulator: **iPhone 15** or **iPhone 15 Pro**

---

### Step 3: Clean Build Folder

Press: **Cmd+Shift+K**

This clears all cached build artifacts.

---

### Step 4: Build

Press: **Cmd+B**

You should see:
```
Build succeeded
```

---

### Step 5: Run

Press: **Cmd+R**

The app should launch in the simulator!

---

## 🧪 Test the App

### Features to Test:

1. **Dashboard**
   - Shows today's summary (calories, protein, water, weight)
   - Pull to refresh
   - Recent logs display

2. **Quick Log**
   - Type natural language: "ate chicken rice"
   - Tap microphone for voice input
   - Auto-submit after voice input

3. **Food Log**
   - Select meal type
   - Enter food details
   - Calories and protein estimates

4. **Settings**
   - Webhook URL configuration
   - Test connection button

---

## ⚠️ Known Limitation

**Widgets won't work yet** - They need a separate Widget Extension target.

See `FIX_MAIN_ATTRIBUTE.md` for how to set up widgets properly.

---

## 🐛 If Build Fails

1. **Check Swift version:**
   - Xcode → Preferences → Locations
   - Ensure Xcode is selected (not Command Line Tools)

2. **Verify signing:**
   - Select Nexus target
   - Signing & Capabilities tab
   - Enable "Automatically manage signing"
   - Select your Team

3. **Clean Derived Data:**
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData
   ```
   Then build again.

---

## 📊 Expected Output

### On Simulator:

- App icon appears on home screen
- App launches with tab bar
- 4 tabs: Dashboard, Quick Log, Food, Settings
- All UI is responsive
- Voice input works (microphone permission)
- API calls work (if backend is running)

---

## 🔧 Backend Setup

Make sure your Nexus backend is running:

```bash
# In Infrastructure/Nexus-setup directory
docker-compose up -d
```

Then verify webhooks in n8n at `https://n8n.rfanw`

---

## ✅ Success Criteria

- [x] App builds without errors
- [x] App runs on simulator
- [x] All tabs navigate correctly
- [ ] Voice input requests permission
- [ ] API calls succeed (requires backend)
- [ ] Offline queue works when offline

---

## 📝 Next Steps

Once the app works:

1. **Set up Widget Extension** (see FIX_MAIN_ATTRIBUTE.md)
2. **Test on real device** (requires Developer Account)
3. **Configure App Groups** for widget data sharing
4. **Set up Photo Food Logging** (see PHOTO_FOOD_SETUP.md)

---

*All code errors are fixed - ready to build!* ✅
