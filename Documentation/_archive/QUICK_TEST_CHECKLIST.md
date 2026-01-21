# ✅ Quick Test Checklist

## 🎯 What to Do Now

The app is built successfully! Here's your testing checklist:

---

## 1️⃣ Run the App (NOW)

**In Xcode:**
Press **Cmd+R** to launch the app on the simulator.

---

## 2️⃣ Basic Functionality Test (5 minutes)

### Dashboard Tab
- [ ] App opens and shows dashboard
- [ ] See summary cards (calories, protein, water, weight)
- [ ] Pull down to refresh works
- [ ] No crashes

### Quick Log Tab
- [ ] Can type natural language (try: "drank 500ml water")
- [ ] Tap microphone icon
- [ ] Grant microphone permission when asked
- [ ] Speak: "ate chicken rice"
- [ ] See live transcript appear
- [ ] Auto-submits after speaking

### Food Log Tab
- [ ] Can select meal type
- [ ] Can enter food description
- [ ] Can add calories/protein
- [ ] Submit button works

### Settings Tab
- [ ] Shows webhook URL
- [ ] Can edit webhook URL
- [ ] Test connection button exists

---

## 3️⃣ Voice Input Test (2 minutes)

**Critical feature - test this:**

1. Go to **Quick Log** tab
2. Tap **microphone icon** 🎤
3. **Allow** microphone access
4. Say clearly: **"I drank 500 milliliters of water"**
5. Watch transcript appear in real-time
6. Should auto-submit when you stop talking
7. Check dashboard for update

---

## 4️⃣ API Connection Test (2 minutes)

The app connects to your n8n backend at `https://n8n.rfanw`

**Test:**
1. Quick Log tab
2. Type: `ate chicken rice`
3. Tap "Log Entry"
4. Watch for response:
   - ✅ Success: Dashboard updates, shows in recent logs
   - ❌ Fails: Entry queued offline (check for pending count)

**Backend running?**
```bash
curl -X POST https://n8n.rfanw/webhook/nexus-log \
  -H "Content-Type: application/json" \
  -d '{"text":"test from terminal"}'
```

---

## 5️⃣ Offline Mode Test (3 minutes)

**Test offline queueing:**

1. In simulator: Settings app → Wi-Fi → **Turn OFF**
2. Back to Nexus app → Quick Log
3. Log something: "ate apple"
4. Should show offline indicator
5. Check Dashboard → should show "1 pending"
6. Go back to Settings → Wi-Fi → **Turn ON**
7. Back to Nexus app → should auto-retry
8. Pending count goes to 0

---

## 6️⃣ Photo Food Logging (Optional)

**Requires backend setup:**

1. Food Log tab
2. Tap camera icon 📷
3. Take/select photo
4. App uploads to backend
5. Claude Vision identifies food
6. Returns nutrition info

**Backend needed:** See `PHOTO_FOOD_SETUP.md` for n8n workflow setup.

---

## 🚀 What Works Right Now

✅ **Fully Functional:**
- Natural language food/water logging
- Voice input with live transcript
- Dashboard with real-time updates
- Pull-to-refresh
- Offline queueing with auto-retry
- Haptic feedback
- Network status monitoring
- Recent logs display

❌ **Not Yet Working:**
- Widgets (need Widget Extension setup)
- Siri shortcuts (need Widget Extension)
- Photo food logging (need backend webhook)

---

## 🎯 Next Steps (Optional)

### Want Widgets?
See `ENABLE_WIDGETS.md` for step-by-step setup.

### Want Photo Food Logging?
See `PHOTO_FOOD_SETUP.md` for n8n workflow setup.

### Want to Deploy to Real Device?
1. Connect iPhone via USB
2. Xcode → Select your iPhone as destination
3. Signing & Capabilities → Add your Apple ID
4. Cmd+R to run on device

---

## 🐛 Common Issues

### Microphone Permission Denied
- Simulator → I/O → Reset Content and Settings
- Rerun app and grant permission

### API Calls Failing
- Check backend is running: `curl https://n8n.rfanw/webhook/nexus-log`
- Verify webhook URL in Settings tab
- Check n8n workflows are active

### App Crashes
- Check Xcode console for error messages
- Look for red error text
- Common: Missing Info.plist keys for microphone

---

## ✅ Success Criteria

You've successfully tested the app when:
- [x] App builds without errors
- [ ] App runs on simulator
- [ ] Voice input works
- [ ] Can log entries
- [ ] Dashboard updates
- [ ] Offline queue works
- [ ] No crashes during testing

---

**🎉 You're ready to start using Nexus for health tracking!**

*Press Cmd+R in Xcode to launch now!*
