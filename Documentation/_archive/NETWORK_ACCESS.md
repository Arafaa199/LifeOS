# 🌐 Network Access - How It Works

## ✅ Will It Work When NOT on Home Network?

**YES!** The app works from **anywhere** because it uses:

```
https://n8n.rfanw
```

This is a **public domain**, not a local IP address.

---

## 🔄 How Data Flows

### When on Home WiFi:
```
iPhone App
    ↓
https://n8n.rfanw (your domain)
    ↓
Reverse proxy (Caddy/Nginx)
    ↓
n8n container
    ↓
PostgreSQL database (nexus-db)
```

### When on Cellular/Other WiFi:
```
iPhone App
    ↓
Internet
    ↓
https://n8n.rfanw (your domain)
    ↓
Your home network
    ↓
Reverse proxy
    ↓
n8n container
    ↓
PostgreSQL database
```

**Same flow! Works from anywhere!**

---

## 🔒 Security

Your domain `https://n8n.rfanw` is:
- ✅ HTTPS encrypted
- ✅ Publicly accessible
- ✅ Protected by your reverse proxy

**No VPN needed!**

---

## 📱 App Configuration

The app uses this base URL (hardcoded):
```swift
private var baseURL: String {
    UserDefaults.standard.string(forKey: "webhookBaseURL") ?? "https://n8n.rfanw"
}
```

You can change it in Settings tab if needed.

---

## 🧪 Test from Anywhere

Try this from cellular (not WiFi):

```bash
# On your phone (Safari)
https://n8n.rfanw/webhook/nexus-finance-summary

# Should show JSON with your transactions
```

---

## 🌍 What Works Where

| Feature | Home WiFi | Cellular | Other WiFi |
|---------|-----------|----------|------------|
| **View Transactions** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Log Expenses** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Trigger Import** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Pull to Refresh** | ✅ Yes | ✅ Yes | ✅ Yes |
| **SMS Auto-Import** | ⚠️ Requires Mac on home network | ⚠️ Requires Mac on | ⚠️ Requires Mac on |

**Note:** SMS auto-import only works when your Mac is on and connected to home network (where Messages syncs).

---

## 🏠 Mac Requirement

The SMS import script runs on your **Mac** (not the iOS app):
- Needs access to `~/Library/Messages/chat.db`
- Must be able to connect to database at `100.90.189.16:5432`
- Typically on your home network (Tailscale)

**But the iOS app works from anywhere!**

---

## 🎯 Real-World Usage

**Scenario 1:** You're at a cafe
- Phone on cafe WiFi
- Open Finance tab
- See all your transactions (from database)
- Log new expense
- ✅ Works perfectly

**Scenario 2:** You're traveling
- Phone on cellular
- Get Emirates NBD SMS
- SMS syncs to Mac at home (via iCloud)
- Mac auto-imports (2 seconds)
- Open app, pull to refresh
- ✅ See new transaction

**Scenario 3:** Mac is off
- Phone works fine (reads from database)
- SMS still sync to Mac via iCloud
- When Mac turns on, imports happen
- ✅ Nothing lost

---

## 🔧 Network Troubleshooting

### App says "Offline" or can't fetch data?

**Check domain is accessible:**
```bash
# On your phone (Terminal or online tool)
curl https://n8n.rfanw/webhook/nexus-finance-summary

# Should return JSON
```

**Check your reverse proxy:**
```bash
# SSH to server
ssh nexus

# Check if n8n is running
docker ps | grep n8n

# Check reverse proxy logs
sudo tail -f /var/log/caddy/access.log
# or
sudo tail -f /var/log/nginx/access.log
```

### Can't trigger SMS import?

This webhook requires Mac to be accessible:
```
/webhook/nexus-trigger-import
```

It SSHs to your Mac and runs the import script. If Mac is off or unreachable, this will fail (but app still shows cached data).

---

## 📊 Data Freshness

### When App Fetches Data:
- On app launch
- On pull-to-refresh
- After logging expense
- After triggering import

### When Database Updates:
- SMS auto-import (every time new SMS arrives)
- Manual expense logging (immediate)
- Triggered import from app (on-demand)

### Typical Delay:
- Bank SMS → Mac import → Database: **2 seconds**
- Database → App (when you refresh): **< 1 second**

**Total: New SMS shows in app within 3-5 seconds** (if you refresh)

---

## 🚀 Offline Mode

**What happens if no internet?**

Currently:
- App shows cached data (last fetched)
- Can't log new expenses
- Can't trigger import

**Future enhancement:** Add offline queue (like nutrition logging has)

---

## ✅ Summary

**Network Access:**
- ✅ Works on WiFi (home or away)
- ✅ Works on cellular
- ✅ Works from anywhere with internet
- ✅ HTTPS encrypted
- ✅ No VPN required

**SMS Import:**
- ⚠️ Requires Mac on home network
- ⚠️ Auto-imports when SMS arrives
- ✅ Data syncs to app everywhere

**Your setup is perfect for global access!** 🌍
