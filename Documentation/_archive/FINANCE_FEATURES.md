# 💰 Finance Tracking Features

## ✅ Added to Nexus App

The app now includes **complete finance tracking** alongside nutrition/health!

---

## 🎯 What's New

### 5th Tab: Finance 💵

Added between Food and Settings tabs with 3 sections:

1. **Quick Expense** - Natural language logging
2. **Transactions** - View all expenses
3. **Budget** - Track spending vs. budgets

---

## 📱 Features

### 1. Quick Expense Logging

**Natural language input:**
```
"$45 at Whole Foods"
"spent $12.50 on coffee"
"$156 groceries at Costco"
"$25 uber to airport"
```

**Claude AI parses:**
- Merchant name
- Amount
- Category (grocery, restaurant, transport, etc.)
- Auto-flags grocery/restaurant

**Today's Summary Card:**
- Total spent today
- Grocery spending
- Eating out spending

**Category Quick Actions:**
- Tap a category to start logging
- 8 common categories with icons

---

### 2. Transactions List

**Features:**
- View all recent transactions
- Pull-to-refresh
- Shows merchant, category, amount
- Color-coded (red = expense, green = income)

**Data:**
- Synced from database
- 20 most recent transactions
- Auto-updates after logging

---

### 3. Budget Overview

**Budget Cards:**
- Monthly budget by category
- Progress bar (green/red)
- Amount spent / budgeted
- Remaining or over-budget warning

**Category Breakdown:**
- Spending by category this month
- Sorted by highest spend
- Quick visual overview

---

## 🗄️ Database Integration

### Finance Schema Tables:

#### finance.transactions
```sql
- id
- date
- merchant_name
- merchant_name_clean
- amount (positive = expense)
- category, subcategory
- is_grocery, is_restaurant, is_food_related
- notes, tags
- created_at
```

#### finance.accounts
```sql
- id
- name
- institution
- account_type
- last_four
- is_active
```

#### finance.budgets
```sql
- id
- month (YYYY-MM-DD)
- category
- budget_amount
```

#### finance.grocery_items
```sql
- id
- transaction_id
- item_name
- quantity, unit
- total_price
- ingredient_id (links to nutrition!)
- category, is_healthy
```

#### finance.merchant_rules
```sql
- merchant_pattern (regex)
- category
- is_grocery, is_restaurant
- store_name
- priority
```

**Pre-seeded merchants:**
- Whole Foods, Trader Joes, Costco
- Walmart, Target, Safeway, Kroger
- DoorDash, Uber Eats, Starbucks
- And more...

---

## 🔗 API Endpoints

### POST /webhook/nexus-expense
**Quick expense logging with natural language**

Request:
```json
{
  "text": "$45 at Whole Foods"
}
```

Response:
```json
{
  "success": true,
  "message": "Logged $45.00 at Whole Foods",
  "data": {
    "transaction": {
      "id": 123,
      "merchant_name": "Whole Foods",
      "amount": 45.00,
      "category": "grocery",
      "is_grocery": true
    },
    "total_spent": 127.50,
    "category_spent": 45.00
  }
}
```

### POST /webhook/nexus-transaction
**Manual transaction entry**

Request:
```json
{
  "merchant_name": "Starbucks",
  "amount": 5.75,
  "category": "restaurant",
  "notes": "Morning coffee",
  "date": "2026-01-20T10:30:00Z"
}
```

### GET /webhook/nexus-finance-summary
**Daily/monthly summary**

Response:
```json
{
  "success": true,
  "data": {
    "total_spent": 245.67,
    "grocery_spent": 125.00,
    "eating_out_spent": 45.50,
    "category_breakdown": {
      "grocery": 125.00,
      "restaurant": 45.50,
      "transport": 35.00,
      "entertainment": 40.17
    },
    "budgets": [
      {
        "category": "grocery",
        "budget_amount": 500.00,
        "spent": 125.00,
        "remaining": 375.00
      }
    ]
  }
}
```

---

## 🛠️ Backend Setup

### 1. n8n Workflow

Import the workflow:
```bash
/Users/rafa/Cyber/Infrastructure/Nexus-setup/n8n-workflows/expense-log-webhook.json
```

**Workflow does:**
1. Receives expense text
2. Uses Claude AI to parse:
   - Merchant name
   - Amount
   - Category
   - Flags (grocery/restaurant)
3. Inserts into finance.transactions
4. Returns daily summary

### 2. Claude AI Integration

The workflow uses **Claude Sonnet 4.5** to parse natural language expenses:

```
Input: "$45 at Whole Foods"

Claude returns:
{
  "merchant_name": "Whole Foods",
  "amount": 45.00,
  "category": "grocery",
  "is_grocery": true,
  "is_restaurant": false,
  "notes": null
}
```

### 3. Merchant Auto-Categorization

Database includes rules for auto-categorizing:
- "WHOLE FOODS" → grocery, is_grocery=true
- "STARBUCKS" → restaurant, is_restaurant=true
- "UBER" → transport

Add custom rules:
```sql
INSERT INTO finance.merchant_rules
(merchant_pattern, category, is_grocery, priority)
VALUES ('%MY STORE%', 'grocery', TRUE, 10);
```

---

## 📊 Cross-Domain Features

### Grocery → Nutrition Link

Grocery items can link to nutrition ingredients:

```sql
SELECT
  gi.item_name,
  gi.total_price,
  i.protein_per_100g,
  ROUND((gi.total_price / (i.protein_per_100g * gi.quantity / 100))::numeric, 2)
    as cost_per_g_protein
FROM finance.grocery_items gi
JOIN nutrition.ingredients i ON gi.ingredient_id = i.id
WHERE i.protein_per_100g > 10
ORDER BY cost_per_g_protein;
```

**Find cheapest protein sources!**

### Daily Summary Integration

The `core.daily_summary` table includes finance:
```sql
- total_spent
- grocery_spent
- eating_out_spent
```

Updated nightly by n8n workflow.

---

## 🎯 Usage Examples

### Quick Logging
1. Open Finance tab
2. Type: "$25 lunch at chipotle"
3. Tap "Log Expense"
4. Dashboard updates immediately

### View Spending
1. Switch to "Transactions" tab
2. See all recent expenses
3. Pull down to refresh

### Check Budget
1. Switch to "Budget" tab
2. See monthly budgets
3. Green = on track, Red = over budget

---

## 🚀 Files Added

### Models
- `Nexus/Models/FinanceModels.swift` - All finance data structures

### Views
- `Nexus/Views/Finance/FinanceView.swift` - Main finance UI with 3 tabs
  - QuickExpenseView
  - TransactionsListView
  - BudgetView

### ViewModels
- `Nexus/ViewModels/FinanceViewModel.swift` - Finance state management

### API
- Updated `Nexus/Services/NexusAPI.swift`:
  - logExpense()
  - addTransaction()
  - fetchFinanceSummary()
  - postFinance()

### UI
- Updated `Nexus/Views/ContentView.swift`:
  - Added Finance tab (position 3)

### Backend
- `n8n-workflows/expense-log-webhook.json` - Claude-powered expense parser

---

## ✅ Complete Feature Set

**Nexus now tracks:**

1. ✅ **Health**
   - Weight, body fat, HRV, sleep
   - Workouts, recovery scores
   - Apple Health / Whoop integration

2. ✅ **Nutrition**
   - Food logging (text/photo)
   - Water tracking
   - Meal planning
   - Ingredients database
   - Protein/calorie goals

3. ✅ **Finance** (NEW!)
   - Expense tracking
   - Budget management
   - Grocery receipts
   - Category spending
   - Merchant auto-categorization

4. 🔜 **Notes**
   - Obsidian integration
   - Daily notes
   - Tags, metadata

5. 🔜 **Home**
   - Home Assistant sensors
   - Kitchen events
   - Device snapshots

---

## 🧪 Test It Now

**In the app simulator:**

1. Run the app (Cmd+R)
2. Tap **Finance** tab (4th tab, dollar sign icon)
3. Type: `$45 at Whole Foods`
4. Tap "Log Expense"
5. Check Today's Spending summary updates

**Requires backend:**
- n8n running at https://n8n.rfanw
- expense-log-webhook.json workflow imported
- Claude AI credential configured

---

## 📝 Next Steps

1. **Import n8n workflow** for expense parsing
2. **Set monthly budgets** in database:
   ```sql
   INSERT INTO finance.budgets (month, category, budget_amount)
   VALUES ('2026-01-01', 'grocery', 500.00);
   ```
3. **Test expense logging** in the app
4. **Add custom merchant rules** for your stores
5. **Link grocery items** to nutrition ingredients

---

**Your complete life tracking hub is ready!** 💪

- 🍎 Track what you eat
- 🏋️ Track your health
- 💵 Track what you spend
- 📊 All in one database
- 🤖 Powered by Claude AI
