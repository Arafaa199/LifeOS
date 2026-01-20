# 📱 Automatic SMS Transaction Import

## ✅ What This Does

Automatically reads bank transaction SMS messages from your macOS Messages app and imports them into Nexus every 15 minutes.

**Supported Banks:**
- ✅ **Emirates NBD** (AED) - Your primary bank!
- ✅ AlRajhi Bank (SAR)
- ✅ Jordan Kuwait Bank (JOD)

---

## 🎯 How It Works

```
iPhone receives bank SMS
        ↓
iMessage syncs to Mac
        ↓
Script reads Messages.app database every 15min
        ↓
Parses transaction details (amount, merchant, date)
        ↓
Imports to finance.transactions table
        ↓
iOS app fetches and displays transactions
```

**Zero manual entry!** All your Emirates NBD transactions appear automatically in the Finance tab.

---

## 🚀 Setup (One-Time)

### Step 1: Enable Messages Sync

**On iPhone:**
1. Settings → Messages
2. Enable "iMessage"
3. Enable "Text Message Forwarding" → Select your Mac

**On Mac:**
1. Messages app → Preferences
2. Sign in with same Apple ID as iPhone
3. Enable "Enable Messages in iCloud"

---

### Step 2: Configure Database Accounts

Add your Emirates NBD account to the database:

```bash
# SSH to Nexus server
ssh nexus

# Access database
docker exec -it nexus-db psql -U nexus nexus

# Add your Emirates NBD account
INSERT INTO finance.accounts (name, institution, account_type, is_active)
VALUES ('Emirates NBD Checking', 'Emirates NBD', 'checking', TRUE);

# Note the account ID (should be 2 if this is your second account)
SELECT id, name FROM finance.accounts;

\q
```

---

### Step 3: Test Manual Import

On your Mac (where Messages app is):

```bash
cd /Users/rafa/Cyber/Infrastructure/Nexus-setup/scripts

# Set database password
export NEXUS_PASSWORD="your_password_here"

# Test import (last 7 days)
node import-sms-transactions.js 7
```

**Expected output:**
```
Found 45 bank messages
Import complete in 2.3s:
  New: 42
  Duplicates: 3
  Skipped: 0
  Errors: 0

Account Summary:
  Emirates NBD: 42 tx, spent 3245.50, received 8500.00
```

---

### Step 4: Set Up Automatic Import

#### Option A: Run on Mac (Recommended)

Create a launchd job to run every 15 minutes:

```bash
# Create plist file
cat > ~/Library/LaunchAgents/com.nexus.sms-import.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.nexus.sms-import</string>

    <key>ProgramArguments</key>
    <array>
        <string>/Users/rafa/Cyber/Infrastructure/Nexus-setup/scripts/auto-import-sms.sh</string>
    </array>

    <key>StartInterval</key>
    <integer>900</integer>

    <key>EnvironmentVariables</key>
    <dict>
        <key>NEXUS_PASSWORD</key>
        <string>YOUR_PASSWORD_HERE</string>
    </dict>

    <key>StandardOutPath</key>
    <string>/tmp/nexus-sms-import.log</string>

    <key>StandardErrorPath</key>
    <string>/tmp/nexus-sms-import-error.log</string>
</dict>
</plist>
EOF

# Replace YOUR_PASSWORD_HERE with actual password
nano ~/Library/LaunchAgents/com.nexus.sms-import.plist

# Load and start
launchctl load ~/Library/LaunchAgents/com.nexus.sms-import.plist
launchctl start com.nexus.sms-import

# Check it's running
launchctl list | grep nexus

# View logs
tail -f /tmp/nexus-sms-import.log
```

#### Option B: Run from n8n (Alternative)

Import the n8n workflow:

```bash
# In n8n web interface:
# Workflows → Import from File
# Select: n8n-workflows/auto-sms-import.json
# Update the command path to your Mac's username
# Activate workflow
```

**Note:** This requires n8n to be running on the same Mac where Messages app is.

---

## 🔧 How Parsing Works

### Emirates NBD Format (Arabic)

**Purchase SMS:**
```
تمت عملية شراء بقيمة AED 125.50 لدى CARREFOUR ,DUBAI
```

**Parsed as:**
- Merchant: "CARREFOUR"
- Amount: -125.50 (expense)
- Currency: AED
- Type: Purchase

**ATM Withdrawal:**
```
تم سحب مبلغ AED 500.00
```

**Parsed as:**
- Merchant: "ATM Withdrawal"
- Amount: -500.00
- Currency: AED
- Type: ATM

**Salary Credit:**
```
تم تحويل راتبك بقيمة AED 15000.00
```

**Parsed as:**
- Merchant: "Salary"
- Amount: 15000.00 (income)
- Currency: AED
- Type: Salary

---

## 📊 In the iOS App

Once imported, transactions appear automatically:

**Finance Tab → Transactions:**
- Shows all imported transactions
- AED currency displayed correctly
- Merchant names from SMS
- Pull to refresh to sync latest

**Finance Tab → Quick:**
- Today's spending in AED
- Grocery vs. Eating Out breakdown
- Recent transactions list

**Dashboard:**
- Total spent today
- Grocery spending
- Eating out spending

---

## 🔍 Verification

### Check if transactions are importing:

```bash
# SSH to Nexus server
ssh nexus

# Check recent imports
docker exec -it nexus-db psql -U nexus nexus -c "
SELECT date, merchant_name, amount, currency, category
FROM finance.transactions
WHERE date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY date DESC, created_at DESC
LIMIT 20;
"
```

### Check today's summary:

```bash
docker exec -it nexus-db psql -U nexus nexus -c "
SELECT
  COUNT(*) as tx_count,
  SUM(CASE WHEN amount < 0 THEN amount ELSE 0 END) as spent,
  SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) as received
FROM finance.transactions
WHERE date = CURRENT_DATE;
"
```

---

## 🐛 Troubleshooting

### No transactions importing

**Check Messages database access:**
```bash
ls -la ~/Library/Messages/chat.db
# Should show the file exists
```

**Grant Full Disk Access:**
1. System Preferences → Security & Privacy → Privacy
2. Select "Full Disk Access"
3. Add Terminal (or your script runner)
4. Add Node.js binary

### Wrong account ID

Edit the script:
```bash
nano /Users/rafa/Cyber/Infrastructure/Nexus-setup/scripts/import-sms-transactions.js

# Update the account_id for Emirates NBD (around line 35):
'EmiratesNBD': {
  account_id: 2,  // Change this to match your database
  currency: 'AED',
  parser: parseEmiratesNBD,
},
```

### Duplicate transactions

The script automatically prevents duplicates using external_id. If you see duplicates, it might be different SMS variations. Check:

```bash
docker exec -it nexus-db psql -U nexus nexus -c "
SELECT merchant_name, amount, date, COUNT(*)
FROM finance.transactions
GROUP BY merchant_name, amount, date
HAVING COUNT(*) > 1;
"
```

---

## 🎯 Adding New Banks

To add a new bank (e.g., ADCB, FAB, Mashreq):

1. **Get SMS format** - Check a few transaction SMS messages
2. **Write parser function** - Copy and modify `parseEmiratesNBD`
3. **Add to BANKS config** - Add sender ID and parser
4. **Add account** - Insert into `finance.accounts` table
5. **Test** - Run manual import to verify

**Example for ADCB:**

```javascript
// In import-sms-transactions.js

const BANKS = {
  // ... existing banks ...

  'ADCB': {
    account_id: 4,
    currency: 'AED',
    parser: parseADCB,
  },
};

function parseADCB(text, msgDate) {
  // Match ADCB SMS format
  const purchaseMatch = text.match(/Purchase of AED ([\d,.]+) at (.+)/i);
  if (purchaseMatch) {
    return {
      date: msgDate,
      merchant: purchaseMatch[2].trim(),
      amount: -parseFloat(purchaseMatch[1].replace(/,/g, '')),
      currency: 'AED',
      type: 'Purchase',
    };
  }
  return null;
}
```

---

## 📈 Advanced Features

### Multi-Currency Support

The app automatically handles multiple currencies:
- Emirates NBD (AED)
- AlRajhi (SAR)
- JKB (JOD)

**Dashboard shows:**
- Primary currency (AED) totals
- Multi-currency transactions in list
- Each transaction shows its currency

### Merchant Auto-Categorization

Transactions are auto-categorized using merchant rules:

```sql
-- Add custom categorization rules
INSERT INTO finance.merchant_rules
(merchant_pattern, category, is_grocery, priority)
VALUES
('%CARREFOUR%', 'grocery', TRUE, 10),
('%SPINNEYS%', 'grocery', TRUE, 10),
('%CHOITHRAMS%', 'grocery', TRUE, 10),
('%WEST ZONE%', 'grocery', TRUE, 10);
```

### Budget Alerts

Set monthly budgets and get alerts:

```sql
-- Set monthly grocery budget
INSERT INTO finance.budgets (month, category, budget_amount)
VALUES ('2026-01-01', 'grocery', 3000.00);  -- 3000 AED/month

-- Check budget status
SELECT
  b.category,
  b.budget_amount,
  COALESCE(SUM(t.amount), 0) as spent,
  b.budget_amount + COALESCE(SUM(t.amount), 0) as remaining
FROM finance.budgets b
LEFT JOIN finance.transactions t
  ON t.category = b.category
  AND DATE_TRUNC('month', t.date) = b.month
WHERE b.month = '2026-01-01'
GROUP BY b.id, b.category, b.budget_amount;
```

---

## ✅ Summary

**After setup, you get:**
- ✅ Automatic transaction import every 15 minutes
- ✅ All Emirates NBD transactions in the app
- ✅ Correct AED currency display
- ✅ Auto-categorization (grocery, restaurant, etc.)
- ✅ Zero manual data entry
- ✅ Historical data import (last 365 days)

**Your Finance tab now shows real transactions from your bank SMS!**

---

## 🚀 Quick Start Command

```bash
# One command to test everything:
cd /Users/rafa/Cyber/Infrastructure/Nexus-setup/scripts && \
export NEXUS_PASSWORD="your_password" && \
node import-sms-transactions.js 30 && \
echo "Check the iOS app Finance tab now!"
```

**Last 30 days of transactions will be imported and visible in the app immediately!**
