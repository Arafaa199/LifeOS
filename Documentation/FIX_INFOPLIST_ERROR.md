# Fix: Multiple commands produce Info.plist

## 🔍 What This Error Means

```
Multiple commands produce
'/Users/rafa/Library/Developer/Xcode/.../Nexus.app/Info.plist'
```

This happens when Xcode tries to process `Info.plist` twice:
1. ✅ As the app's Info.plist (correct)
2. ❌ As a resource to copy (incorrect)

---

## ✅ Quick Fix (1 minute)

### Step 1: Open Project
```bash
cd /Users/rafa/Cyber/Dev/Nexus-mobile
open Nexus.xcodeproj
```

### Step 2: Remove Info.plist from Copy Bundle Resources

**Visual Guide:**

```
Xcode Window
├── Left Sidebar (Project Navigator)
│   └── Click: Nexus (project icon at top)
│       └── Under TARGETS, click: Nexus
│
├── Top Tabs
│   └── Click: Build Phases
│
└── Main Area
    └── Find section: "Copy Bundle Resources"
        └── Click ▶ to expand
            └── Look for: Info.plist
                └── If found:
                    1. Click to select it
                    2. Click the "−" (minus) button
                    3. It will be removed ✅
```

### Step 3: Clean & Build

1. **Clean Build Folder**
   - Menu: Product → Clean Build Folder
   - Or press: **Cmd+Shift+K**

2. **Build**
   - Menu: Product → Build
   - Or press: **Cmd+B**

**Should build successfully!** ✅

---

## 🎯 Detailed Instructions (If You Need More Help)

### Where to Find It:

1. **In Xcode, left sidebar:**
   - Click the blue **Nexus** icon (project file)
   - You'll see:
     ```
     PROJECT
       Nexus
     TARGETS
       Nexus          ← Click this one
     ```

2. **Top of window, click "Build Phases" tab:**
   ```
   General | Signing & Capabilities | Resource Tags | Info | Build Settings | Build Phases | Build Rules
                                                                              ^^^^^^^^^^^^^^^^
                                                                              Click here
   ```

3. **Look for section "Copy Bundle Resources":**
   ```
   ▶ Copy Bundle Resources (X items)
   ```
   Click the ▶ to expand it

4. **Inside, you'll see a list:**
   ```
   Name                          Type
   Assets.xcassets              folder
   Info.plist                   property list    ← Remove this one!
   Preview Assets.xcassets      folder
   ```

5. **Select `Info.plist` and click the "−" button below**

6. **It should disappear from the list** ✅

---

## ✅ What Info.plist SHOULD Look Like

After fixing, here's where Info.plist should be:

### ✅ Correct:
- **Build Settings** → Search "Info.plist"
  - `INFOPLIST_FILE = Nexus/Info.plist` ✅

### ❌ Incorrect:
- **Build Phases** → Copy Bundle Resources
  - Info.plist should NOT be here! ❌

---

## 🐛 Alternative: Check for Duplicates

If removing from Copy Bundle Resources doesn't work, check for duplicate entries:

1. **Build Phases** → **Copy Bundle Resources**
2. Look for **multiple** Info.plist entries
3. Remove ALL of them
4. Clean build folder
5. Build again

---

## 🔧 Nuclear Option: Reset Build Phases

If still not working:

1. **Right-click on "Copy Bundle Resources"**
2. **Delete** the entire section
3. **Click "+" below** to add it back
4. **Add only:**
   - `Assets.xcassets`
   - `Preview Assets.xcassets` (if exists)
5. **Do NOT add Info.plist**
6. Clean & Build

---

## ✅ Success Criteria

After fixing, you should see:

```bash
# Build output (Cmd+B)
Build succeeded
0 errors, 0 warnings
```

No more "Multiple commands" error! 🎉

---

## 📊 Common Mistakes

### ❌ Wrong: Info.plist in 2 places
```
Build Settings:
  INFOPLIST_FILE = Nexus/Info.plist

Build Phases → Copy Bundle Resources:
  Info.plist                     ← Remove this!
```

### ✅ Correct: Info.plist in 1 place only
```
Build Settings:
  INFOPLIST_FILE = Nexus/Info.plist ✅

Build Phases → Copy Bundle Resources:
  Assets.xcassets
  Preview Assets.xcassets
  (no Info.plist!)              ✅
```

---

## 🚀 After It Builds

Once you get "Build succeeded":

1. **Run the app** (Cmd+R)
2. App should launch in simulator
3. See **TESTING_GUIDE.md** for testing

---

## 💡 Why This Happened

When creating an Xcode project:
- Xcode auto-added Info.plist to Copy Bundle Resources (bug)
- This caused it to be processed twice
- Simple fix: remove from Copy Bundle Resources

**Very common issue - you did nothing wrong!** ✅

---

## 📞 Still Having Issues?

If the error persists after removing Info.plist:

1. **Check Console:**
   - View → Navigators → Show Report Navigator (Cmd+9)
   - Click latest build
   - Look for actual error

2. **Verify file location:**
   ```bash
   ls -la Nexus/Info.plist
   # Should exist ✅
   ```

3. **Check Build Settings:**
   - Search: "Info.plist File"
   - Should be: `Nexus/Info.plist`

4. **Clean everything:**
   ```bash
   # Close Xcode first!
   rm -rf ~/Library/Developer/Xcode/DerivedData/Nexus-*

   # Reopen Xcode
   open Nexus.xcodeproj

   # Build (Cmd+B)
   ```

---

*This is a standard Xcode configuration issue and easily fixed!*
*Just remove Info.plist from Copy Bundle Resources. That's it!* ✅
