# 🎉 Automatic Bank Transaction Import

## What You Asked For

> "it should auto read from my messages"

**Done!** The app now automatically imports transactions from your Emirates NBD SMS messages.

---

## 🚀 One-Command Setup

On your Mac (where Messages app is):

```bash
cd /Users/rafa/Cyber/Infrastructure/Nexus-setup/scripts
./setup-auto-import.sh
```

**That's it!** Enter your database password and it's done.

---

## How It Works

```
Emirates NBD sends SMS → iPhone
            ↓
     iMessage syncs to Mac
            ↓
  Script reads every 15 min
            ↓
   Imports to Nexus database
            ↓
  App shows transactions (AED)
```

**Zero manual entry!**

---

## What You'll See

### Finance Tab (iOS App)

**Today's Spending:**
```
AED 245.50    ← Correct currency!
```

**Transactions List:**
```
Carrefour          AED 125.50
Starbucks          AED 18.00
Emirates Petrol    AED 102.00
```

All from your bank SMS - automatically!

---

## Currency Fixed

- ✅ Shows **AED** (not $)
- ✅ Emirates NBD: AED
- ✅ AlRajhi Bank: SAR
- ✅ Jordan Kuwait Bank: JOD

Each transaction displays its correct currency.

---

## Files Created

### Backend Scripts:
1. `scripts/auto-import-sms.sh` - Runs import automatically
2. `scripts/setup-auto-import.sh` - One-command setup
3. `n8n-workflows/auto-sms-import.json` - n8n automation

### App Updates:
- Updated currency support (AED, SAR, JOD)
- Transaction model includes currency
- UI displays correct currency symbols
- formatAmount() helper for all currencies

### Documentation:
- `SMS_AUTO_IMPORT.md` - Complete setup guide
- `AUTO_SMS_SETUP.md` - This file (quick start)

---

## Test It Now

### Step 1: Run Setup

```bash
cd /Users/rafa/Cyber/Infrastructure/Nexus-setup/scripts
./setup-auto-import.sh
```

### Step 2: Check Import

```bash
# View imported transactions
ssh nexus
docker exec -it nexus-db psql -U nexus nexus -c "
SELECT date, merchant_name, amount, currency
FROM finance.transactions
WHERE date >= CURRENT_DATE - 7
ORDER BY date DESC
LIMIT 20;
"
```

### Step 3: Open iOS App

1. Build & Run app (Cmd+R)
2. Go to Finance tab
3. See your Emirates NBD transactions!

---

## Import History

The script can import historical data:

```bash
# Import last 30 days
node import-sms-transactions.js 30

# Import last year
node import-sms-transactions.js 365
```

All your past transactions will appear in the app!

---

## Automatic Schedule

After setup, imports run:
- **Every 15 minutes** automatically
- Checks for new SMS messages
- Imports new transactions
- Updates app immediately

---

## Verify It's Working

```bash
# Check if launchd job is running
launchctl list | grep nexus

# View import logs
tail -f /tmp/nexus-sms-import.log

# Should show:
# [2026-01-20 10:15:00] Starting automatic SMS import...
# Found 3 bank messages
# Import complete in 0.8s:
#   New: 3
#   Duplicates: 0
```

---

## Troubleshooting

### No transactions importing?

**Grant Full Disk Access:**
1. System Preferences → Security & Privacy
2. Privacy → Full Disk Access
3. Add Terminal and Node

**Check Messages sync:**
- Messages app → Preferences
- Enable "iMessage in iCloud"
- Same Apple ID as iPhone

### Wrong currency showing?

The app defaults to AED. If you see USD:
- Make sure transactions have currency field
- Check database: `SELECT currency FROM finance.transactions LIMIT 5;`
- Update summary currency in FinanceViewModel

---

## What's Automatic Now

✅ **Transaction Import**
- Every 15 minutes from Messages app
- Emirates NBD SMS → Database → App

✅ **Currency Detection**
- AED for Emirates NBD
- SAR for AlRajhi
- JOD for JKB

✅ **Merchant Parsing**
- Merchant name from SMS
- Amount and date
- Transaction type (Purchase, ATM, etc.)

✅ **Auto-Categorization**
- Grocery stores
- Restaurants
- ATM withdrawals
- Salary deposits

---

## Next Level Features

### Add More Banks

To add ADCB, FAB, Mashreq, etc.:

1. Check SMS format
2. Write parser function
3. Add to BANKS config
4. Test import

See `SMS_AUTO_IMPORT.md` for full guide.

### Set Budgets

```sql
-- Monthly grocery budget (3000 AED)
INSERT INTO finance.budgets (month, category, budget_amount)
VALUES ('2026-01-01', 'grocery', 3000.00);
```

App will show progress bars and alerts!

### Merchant Rules

```sql
-- Auto-categorize merchants
INSERT INTO finance.merchant_rules
(merchant_pattern, category, is_grocery)
VALUES
('%CARREFOUR%', 'grocery', TRUE),
('%SPINNEYS%', 'grocery', TRUE);
```

---

## 🎉 Summary

**Before:** Manual expense entry in dollars

**Now:**
- ✅ Automatic import from Emirates NBD SMS
- ✅ Correct currency (AED)
- ✅ Zero manual entry
- ✅ Every 15 minutes
- ✅ Historical import (last 365 days)

**All your transactions auto-sync to the app!**

---

## Build & Test

```bash
# In Xcode
Cmd+Shift+K  # Clean
Cmd+B        # Build
Cmd+R        # Run

# Check Finance tab
# Pull to refresh
# See Emirates NBD transactions in AED!
```

**Ready!** 🚀
