# 🚀 Event-Based SMS Import - Three Options

You asked for **event-based** import that triggers when you get a message. Here are your options:

---

## Option 1: 📱 **Trigger from iOS App** (Manual)

**What:** Tap a button in the Finance tab to import latest SMS

**How it works:**
```
You tap sync button in app
        ↓
App calls webhook
        ↓
Webhook SSHs to your Mac
        ↓
Mac runs import script
        ↓
Transactions appear in app
```

**Setup:**

1. **Import n8n workflow:**
   ```bash
   # In n8n: Import from File
   # Select: n8n-workflows/trigger-sms-import.json
   # Activate workflow
   ```

2. **Build & run app:**
   ```bash
   # In Xcode
   Cmd+B
   Cmd+R
   ```

3. **Use it:**
   - Open Finance tab
   - Tap refresh icon (top right)
   - Wait 2-3 seconds
   - Transactions update!

**Pros:**
- ✅ Works anywhere (on cellular, wifi, etc.)
- ✅ Import on-demand
- ✅ Built into the app UI

**Cons:**
- ❌ Manual (requires tap)
- ❌ Requires n8n to SSH to your Mac

---

## Option 2: ⚡ **Auto-Trigger on New SMS** (Event-Based) ⭐ BEST

**What:** Automatically imports within seconds when bank SMS arrives

**How it works:**
```
Bank SMS arrives on iPhone
        ↓
Syncs to Mac Messages
        ↓
fswatch detects file change
        ↓
Immediately runs import (1-2 sec delay)
        ↓
Transactions appear in app
```

**Setup:**

```bash
# On your Mac
cd /Users/rafa/Cyber/Infrastructure/Nexus-setup/scripts

# Install fswatch (file system watcher)
brew install fswatch

# Copy launchd plist
cp com.nexus.sms-watcher.plist ~/Library/LaunchAgents/

# Edit to add your password
nano ~/Library/LaunchAgents/com.nexus.sms-watcher.plist
# Replace: REPLACE_WITH_YOUR_PASSWORD

# Load and start
launchctl load ~/Library/LaunchAgents/com.nexus.sms-watcher.plist

# Verify it's running
launchctl list | grep nexus
tail -f /tmp/nexus-sms-watcher.log
```

**Test it:**
1. Send yourself a test transaction SMS (or wait for a real one)
2. Watch the log: `tail -f /tmp/nexus-sms-watcher.log`
3. Should see: `[date] New message detected, importing...`
4. Open iOS app → Finance tab → See new transaction!

**Pros:**
- ✅ Fully automatic
- ✅ Triggers within 1-2 seconds of SMS arrival
- ✅ No manual action needed
- ✅ Always running in background

**Cons:**
- ❌ Requires Mac to be on and Messages synced
- ❌ Small battery impact (minimal)

---

## Option 3: ⏱️ **Scheduled Import** (Every 15 min)

**What:** Automatically checks for new SMS every 15 minutes

**How it works:**
```
launchd timer fires every 15 min
        ↓
Runs import script
        ↓
Checks for SMS from last 15 min
        ↓
Imports any new transactions
```

**Setup:**

```bash
cd /Users/rafa/Cyber/Infrastructure/Nexus-setup/scripts
./setup-auto-import.sh
```

**Pros:**
- ✅ Fully automatic
- ✅ Reliable
- ✅ Low resource usage

**Cons:**
- ❌ Up to 15 minute delay
- ❌ Imports even when no new SMS (wastes CPU)

---

## 🎯 **Recommended Setup: Option 2 (Event-Based)**

This gives you **instant imports** when SMS arrives!

### Quick Setup Commands:

```bash
# 1. Install fswatch
brew install fswatch

# 2. Navigate to scripts
cd /Users/rafa/Cyber/Infrastructure/Nexus-setup/scripts

# 3. Copy launchd plist
cp com.nexus.sms-watcher.plist ~/Library/LaunchAgents/

# 4. Add your password
nano ~/Library/LaunchAgents/com.nexus.sms-watcher.plist
# Edit line with REPLACE_WITH_YOUR_PASSWORD

# 5. Start the watcher
launchctl load ~/Library/LaunchAgents/com.nexus.sms-watcher.plist

# 6. Verify it's running
ps aux | grep watch-messages
```

### What You'll See:

**In Terminal:**
```bash
tail -f /tmp/nexus-sms-watcher.log

# Output:
[2026-01-20 14:23:15] Starting Messages watcher...
Watching: /Users/rafa/Library/Messages/chat.db
Press Ctrl+C to stop

[2026-01-20 14:25:42] New message detected, importing...
Found 1 bank messages
Import complete in 0.3s:
  New: 1
  Duplicates: 0
[2026-01-20 14:25:43] Import complete
```

**In iOS App:**
- Finance tab shows new transaction
- AED 125.50 from Carrefour
- Within 2-3 seconds of SMS arrival!

---

## 🔧 How fswatch Works

`fswatch` watches file changes in real-time:

```bash
# Manual test (see what it does)
fswatch -o ~/Library/Messages/chat.db

# Output (when new message arrives):
1    ← File changed once
```

When Messages.app receives SMS:
1. Updates `chat.db` SQLite file
2. fswatch detects change
3. Triggers import script
4. Script only imports last 15 minutes
5. Super fast (0.3 seconds typical)

---

## 📊 Comparison Table

| Feature | Option 1 (Tap) | Option 2 (Event) | Option 3 (Schedule) |
|---------|---------------|------------------|---------------------|
| **Automatic** | ❌ Manual | ✅ Yes | ✅ Yes |
| **Speed** | Instant | 1-2 seconds | Up to 15 min |
| **Requires Mac On** | No (uses SSH) | Yes | Yes |
| **Battery Impact** | None | Minimal | Minimal |
| **Setup Complexity** | Medium | Easy | Easy |
| **Best For** | On-demand sync | Real-time sync | Background sync |

---

## 🎮 Controls

### Start Event-Based Watcher:
```bash
launchctl load ~/Library/LaunchAgents/com.nexus.sms-watcher.plist
```

### Stop Event-Based Watcher:
```bash
launchctl unload ~/Library/LaunchAgents/com.nexus.sms-watcher.plist
```

### Check Status:
```bash
# Is it running?
launchctl list | grep nexus

# View live logs
tail -f /tmp/nexus-sms-watcher.log

# View errors
tail -f /tmp/nexus-sms-watcher-error.log
```

### Manual Test:
```bash
# Test import manually
cd /Users/rafa/Cyber/Infrastructure/Nexus-setup/scripts
export NEXUS_PASSWORD="your_password"
node import-sms-transactions.js 1  # Last day
```

---

## 🔒 Security Note

The launchd plist contains your database password in plain text.

**Secure it:**
```bash
# Set permissions (only you can read)
chmod 600 ~/Library/LaunchAgents/com.nexus.sms-watcher.plist

# Verify
ls -la ~/Library/LaunchAgents/com.nexus.sms-watcher.plist
# Should show: -rw------- (600)
```

**Alternative:** Use macOS Keychain:
```bash
# Store password in keychain
security add-generic-password -a nexus -s nexus-db -w "your_password"

# Update script to read from keychain
# (requires code modification)
```

---

## 🐛 Troubleshooting

### Watcher not starting?

```bash
# Check launchd errors
launchctl error com.nexus.sms-watcher

# Check logs
cat /tmp/nexus-sms-watcher-error.log

# Common issues:
# 1. Path wrong - update paths in plist
# 2. fswatch not installed - brew install fswatch
# 3. Password wrong - check NEXUS_PASSWORD
```

### Not importing?

```bash
# Test Messages database access
ls -la ~/Library/Messages/chat.db

# Grant Full Disk Access:
# System Preferences → Security → Privacy → Full Disk Access
# Add: /usr/bin/node
```

### Imports duplicates?

The script has built-in duplicate detection using MD5 hash of:
- Sender + Date + Message Text

Duplicates are automatically skipped.

---

## 🎉 Summary

**Best option: Event-Based (Option 2)**

After setup:
- ✅ Bank SMS arrives
- ✅ Auto-imports within 2 seconds
- ✅ Shows in Finance tab
- ✅ Correct currency (AED)
- ✅ Zero manual work

**Setup time:** 2 minutes

**One command:**
```bash
brew install fswatch && \
cp /Users/rafa/Cyber/Infrastructure/Nexus-setup/scripts/com.nexus.sms-watcher.plist ~/Library/LaunchAgents/ && \
nano ~/Library/LaunchAgents/com.nexus.sms-watcher.plist && \
launchctl load ~/Library/LaunchAgents/com.nexus.sms-watcher.plist && \
tail -f /tmp/nexus-sms-watcher.log
```

**That's it!** Your transactions will auto-import instantly! 🚀
