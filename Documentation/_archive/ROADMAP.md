# 🗺️ Nexus Roadmap - What's Next?

## ✅ What's Working Right Now

### Backend (Nexus Database)
- ✅ PostgreSQL with complete schema (health, nutrition, finance, notes, home)
- ✅ SMS auto-import (79 Emirates NBD transactions imported)
- ✅ Event-based watcher (imports within 2 seconds)
- ✅ n8n webhooks for data access
- ✅ Multi-currency support (AED, SAR, JOD)

### iOS App (Nexus Mobile)
- ✅ Dashboard - Shows daily summary
- ✅ Quick Log - Natural language + voice input
- ✅ Food Log - Detailed nutrition tracking
- ✅ Finance Tab - Transactions list, spending summary
- ✅ Settings - Webhook configuration
- ✅ Offline queue - Auto-retry failed requests
- ✅ Pull-to-refresh everywhere
- ✅ Haptic feedback
- ✅ Multi-currency display

---

## 🚧 What's Missing (Prioritized)

### Tier 1: Critical Features (Do Next) 🔥

#### 1. **Complete Finance Features** (2-3 hours)
**Why:** Finance tab is half-done - let's finish it!

**Missing:**
- [ ] Budget setting/editing in app
- [ ] Budget alerts when over-spending
- [ ] Manual expense logging (not just SMS)
- [ ] Category breakdown charts
- [ ] Monthly/weekly spending trends
- [ ] Export transactions (CSV)

**Impact:** High - You just added finance, make it fully functional!

---

#### 2. **Widgets** (1-2 hours)
**Why:** Quick glance at stats without opening app

**Missing:**
- [ ] Create Widget Extension target
- [ ] Daily summary widget (calories, protein, water, spending)
- [ ] Quick log widget (tap to log)
- [ ] Interactive buttons (iOS 17+)
- [ ] Siri Shortcuts integration

**Impact:** High - Very iOS-native, super useful!

---

#### 3. **Health Metrics Tracking** (2-3 hours)
**Why:** Database has health schema, app doesn't use it

**Missing:**
- [ ] Weight logging and trends
- [ ] Sleep tracking (manual or Apple Health)
- [ ] Workout logging
- [ ] Body composition tracking
- [ ] HRV, recovery scores (if you have Whoop)

**Impact:** Medium - Completes the "life tracking hub" vision

---

### Tier 2: Nice to Have (Later)

#### 4. **Analytics & Visualizations** (3-4 hours)
- [ ] Spending charts (by category, over time)
- [ ] Nutrition trends (calories, protein over weeks)
- [ ] Weight loss/gain graphs
- [ ] Budget vs. actual comparison charts
- [ ] Correlation insights (spending vs. nutrition, etc.)

**Impact:** Medium - Makes data actionable

---

#### 5. **Photo Food Logging** (1-2 hours)
- [ ] Test existing photo webhook
- [ ] Camera integration in Food Log tab
- [ ] Claude Vision integration
- [ ] Auto-fill nutrition from photo

**Impact:** Low-Medium - Cool but not essential

---

#### 6. **Notes Integration** (Obsidian) (2-3 hours)
- [ ] Sync daily notes metadata to database
- [ ] Link food logs to daily notes
- [ ] Link finance to notes
- [ ] Tags, backlinks tracking

**Impact:** Low - Only if you use Obsidian heavily

---

### Tier 3: Advanced (Future)

#### 7. **Home Assistant Integration**
- [ ] Sync kitchen events to database
- [ ] Device snapshots tracking
- [ ] Automate based on habits

**Impact:** Low - Very specific use case

---

#### 8. **Apple Health Sync**
- [ ] Auto-import steps, workouts, sleep
- [ ] Background sync
- [ ] HealthKit integration

**Impact:** Medium - Reduces manual entry

---

## 🎯 My Recommendation: Next 3 Steps

### **Step 1: Complete Finance (2-3 hours)** 🏆

**What to add:**
1. **Manual Expense Logging** - Add transaction form
2. **Budget Management** - Set monthly budgets in app
3. **Spending Charts** - Category breakdown pie chart
4. **Export** - CSV export for taxes/accounting

**Why:** You just built finance, it's 70% done. Finish it to make it super useful!

**Files to create:**
- `Views/Finance/AddExpenseView.swift` - Manual entry form
- `Views/Finance/BudgetSettingView.swift` - Set budgets
- `Views/Finance/SpendingChartsView.swift` - Pie/bar charts
- `n8n-workflows/finance-set-budget.json` - Budget API

---

### **Step 2: Add Widgets (1-2 hours)** 📊

**What to add:**
1. Create Widget Extension target in Xcode
2. Daily Summary widget (shows today's stats)
3. Quick log widget (tap to log)
4. App Shortcuts for Siri

**Why:** Very iOS-native, makes Nexus feel like a real app!

**Files to create:**
- Widget Extension target
- Move widget files to extension
- Enable App Groups

---

### **Step 3: Test & Polish (1 hour)** ✨

**What to fix:**
1. Test all features end-to-end
2. Fix any UI bugs
3. Add loading states everywhere
4. Error handling improvements
5. Better empty states

**Why:** Make what you have rock-solid before adding more!

---

## 📊 Feature Comparison

| Feature | Backend Ready? | App Ready? | Priority |
|---------|----------------|------------|----------|
| **Finance Tracking** | ✅ Yes | 🟡 Partial | 🔥 High |
| **Widgets** | ✅ Yes | ❌ No | 🔥 High |
| **Health Metrics** | ✅ Yes | ❌ No | 🟡 Medium |
| **Nutrition Tracking** | ✅ Yes | ✅ Yes | ✅ Done |
| **Analytics/Charts** | ✅ Yes | ❌ No | 🟡 Medium |
| **Photo Food** | 🟡 Partial | 🟡 Partial | 🟢 Low |
| **Notes (Obsidian)** | ✅ Yes | ❌ No | 🟢 Low |
| **Home Assistant** | ✅ Yes | ❌ No | 🟢 Low |

---

## 🤔 Which Path?

### **Path A: Complete Finance First** (Recommended)
```
Day 1: Manual expense entry, budgets
Day 2: Charts, analytics
Day 3: Widgets
Result: Finance tab is world-class!
```

### **Path B: Add Widgets First**
```
Day 1: Widget Extension setup
Day 2: Daily summary widget
Day 3: Back to finance features
Result: Home screen widgets working!
```

### **Path C: Add Health Tracking**
```
Day 1: Weight logging
Day 2: Sleep, workouts
Day 3: Apple Health sync
Result: True "life tracking hub"!
```

---

## 📈 Long-Term Vision

**What Nexus Could Become:**

1. **Personal Analytics Platform**
   - Correlate spending with nutrition
   - Track weight trends vs. food intake
   - Budget optimization based on habits

2. **AI-Powered Insights**
   - "You spend more on food when stressed"
   - "Your protein intake is below target"
   - "Budget alert: Grocery spending 80% of monthly limit"

3. **Complete Life Dashboard**
   - Health + Nutrition + Finance + Notes + Home
   - All in one place
   - All powered by Claude AI
   - All stored in your own database

---

## 🎯 Quick Decision Matrix

**Want to make money tracking amazing?**
→ **Complete Finance** (Path A)

**Want iOS home screen integration?**
→ **Add Widgets** (Path B)

**Want to track your body metrics?**
→ **Add Health Tracking** (Path C)

**Want to see pretty charts?**
→ **Add Analytics** (Tier 2)

**Want to test what exists first?**
→ **Polish & Test** (Step 3)

---

## ⏱️ Time Estimates

| Task | Time | Difficulty |
|------|------|------------|
| Complete Finance | 2-3 hours | Medium |
| Add Widgets | 1-2 hours | Easy |
| Health Tracking | 2-3 hours | Medium |
| Analytics/Charts | 3-4 hours | Hard |
| Photo Food | 1-2 hours | Easy |
| Notes Integration | 2-3 hours | Medium |

---

## 💡 My Personal Recommendation

**Do this order:**

1. **Complete Finance** (today) - Make what you built fully functional
2. **Add Widgets** (tomorrow) - Home screen integration
3. **Test & Polish** (1 hour) - Make it rock-solid
4. **Add Health Tracking** (next week) - Complete the vision

**Total: ~6-8 hours to have a complete, polished app!**

---

## 🚀 Next Action

**Tell me which you want:**

A. "Complete Finance features"
B. "Add Widgets"
C. "Add Health Tracking"
D. "Something else"

**Or I can start with Path A (Complete Finance) right now!** 💰

What sounds most useful to you?
