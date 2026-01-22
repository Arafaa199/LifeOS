# Nexus Data Entry Guide

**Goal**: Zero-friction logging. Speak naturally, Claude understands.

## Quick Reference

| What | Fastest Method | Example |
|------|---------------|---------|
| **Food** | Voice (Siri/Telegram) | "Chicken and rice for lunch" |
| **Water** | Widget tap | Tap → "1 glass" |
| **Weight** | Auto (smart scale) | Step on scale |
| **Mood** | Evening automation | 9pm prompt → tap 1-10 |
| **Habits** | Voice | "Mark meditation done" |
| **Batch meal** | Claude Code | "Create stir fry batch, 5 portions" |

---

## All Input Methods

### 1. Claude Code (You're here)

The most powerful interface. Just talk naturally:

```
"Log breakfast: 2 eggs and avocado toast"
"I had the chicken stir fry, serving 2 of 5"
"Add milk and eggs to shopping list"
"How much protein today?"
"What's my weight trend this week?"
```

**Setup**: Install MCP server (see `mcp-server/README.md`)

---

### 2. iOS Shortcuts (Siri / Widget)

**Voice**: "Hey Siri, log food" → speak what you ate

**Widget**: Home screen widget for one-tap logging

| Shortcut | Trigger |
|----------|---------|
| Log Food | "Hey Siri, log food" or widget |
| Log Water | Widget tap (pre-set 250ml) |
| Log Weight | "Hey Siri, log weight" |
| Log Mood | Evening automation |
| Quick Nexus | Universal - Claude interprets |

**Setup**: See `ios-shortcuts/README.md`

---

### 3. Telegram Bot

Message your personal bot anytime:

```
You: eggs and bacon for breakfast
Bot: ✓ Logged: breakfast - 2 eggs, bacon. ~350 cal, 25g protein

You: how much protein today?
Bot: Today: 87g protein (58% of 150g goal)

You: add chicken to shopping list
Bot: ✓ Added: chicken breast
```

**Setup**:
1. Create bot via @BotFather
2. Import `n8n-workflows/telegram-bot.json`
3. Add bot token to n8n

---

### 4. Automatic (No Input)

These sync automatically via Home Assistant → n8n → Nexus:

| Data | Source | Frequency |
|------|--------|-----------|
| Weight | Smart scale | On measurement |
| Body fat | Smart scale | On measurement |
| Recovery | Whoop | Daily (via HA) |
| HRV | Whoop | Daily |
| Sleep | Whoop | Daily |
| Strain | Whoop | Daily |
| Steps | Apple Health | Hourly |

**Setup**: Import `n8n-workflows/health-metrics-sync.json`

---

### 5. Smart Food Scale (Future)

Place food on scale, say what it is:

```
[Place chicken on scale]
Scale: 150g detected
You: "Chicken breast"
System: ✓ Logged: chicken breast, 150g - 248 cal, 47g protein
```

**Hardware**: ESP32 + HX711 + Load cell
**Status**: Planned (see `Overall_Setup.md` Upcoming Projects)

---

### 6. Photo Logging (Future)

Snap a photo, Claude estimates:

```
[Photo of plate]
Claude: I see grilled salmon (~150g), rice (~1 cup), broccoli
        Estimated: 520 cal, 42g protein, 45g carbs, 18g fat
        Log this? [Yes/No]
```

**Status**: Possible now via share sheet → n8n → Claude Vision

---

## Natural Language Commands

### Food Logging

```
"2 eggs for breakfast"
"Had a chicken salad, about 400 calories"
"Coffee with milk"
"Ate out - burger and fries, estimate it"
"Leftover stir fry, serving 3 of 5"
"Skip tracking this meal" (low confidence log)
```

### Batch Meals

```
"Made chicken stir fry: 800g chicken, 400g rice, 300g broccoli. 5 portions"
"Create meal: overnight oats, 4 servings, 350 cal each"
"I ate one serving of the stir fry"
"How many portions left of the curry?"
```

### Water

```
"Log water" (default 250ml)
"Had 2 glasses of water"
"500ml water"
```

### Health

```
"Weight 75.5"
"Log 76kg"
"Took my vitamins"
"Creatine and omega-3"
```

### Mood & Habits

```
"Mood 7, energy 6"
"Feeling tired, energy 4"
"Did meditation"
"Mark exercise done"
"Completed reading"
```

### Shopping & Pantry

```
"Add milk, eggs, chicken to shopping list"
"Need to buy spinach"
"Used the last of the rice"
"Bought groceries" (prompts for items)
```

### Queries

```
"How much protein today?"
"What did I eat yesterday?"
"Show this week's calories"
"What batch meals do I have?"
"What's low in the pantry?"
"Am I on track for my goals?"
```

---

## Reducing Friction

### 1. Batch Meal Workflow

Instead of logging every ingredient every time:

**Once**: "Made chicken stir fry: 800g chicken, 400g rice, 300g broccoli. 5 portions"

**Then just**: "Stir fry, serving 2" (macros auto-calculated)

### 2. Favorites/Templates

Common meals get learned:
- "The usual breakfast" → 2 eggs, toast, coffee
- "Post-workout shake" → protein shake, 30g protein
- "Quick lunch" → your default lunch

### 3. Smart Defaults

- Meal time inferred from clock
- Portion sizes default to 1
- Water defaults to 250ml
- Missing macros estimated by Claude

### 4. Contextual Prompts

Home Assistant triggers reminders:
- Kitchen activity detected → "What are you cooking?"
- Meal time passed with no log → gentle reminder
- Evening → mood check-in prompt

---

## Data Confidence Levels

Not sure about calories? That's fine:

| Confidence | When to Use |
|------------|-------------|
| **High** | You measured/know exact amounts |
| **Medium** | Good estimate, common foods |
| **Low** | Restaurant, rough guess, ate out |

Claude assigns confidence automatically based on your description.

---

## Quick Setup Checklist

- [ ] Install MCP server for Claude Code
- [ ] Import n8n workflows
- [ ] Create Telegram bot
- [ ] Set up iOS shortcuts
- [ ] Configure HA health sync
- [ ] Test: "Log breakfast: coffee and toast"
