# Nexus App - UI/UX Design Brief

## Overview
**Nexus** is a personal life operating system that tracks health, finance, nutrition, home automation, and productivity in one unified iOS app. It syncs with a PostgreSQL backend via webhooks and integrates with WHOOP, Apple Health, Home Assistant, Apple Music, and Apple Reminders.

**Target User**: Single power user (the developer) who wants a unified dashboard for all life metrics.

**Platform**: iOS 17+ (iPhone primary, iPad secondary)

---

## Current Design System

### Brand Colors
| Token | Hex | Usage |
|-------|-----|-------|
| `nexusPrimary` | #FF005E | Primary brand - hot pink/magenta |
| `nexusAccent` | #E4D5C3 | Secondary - warm cream |
| `nexusFood` | #D4882A | Food/nutrition - warm amber |
| `nexusWater` | #3A7CA5 | Hydration - muted teal |
| `nexusHealth` | #5A9E6F | Health metrics - sage green |
| `nexusFinance` | #FF005E | Finance - same as primary |
| `nexusMood` | #8B5E83 | Mood tracking - dusty plum |
| `nexusSuccess` | #5A9E6F | Positive states - sage green |
| `nexusWarning` | #D4882A | Warnings - warm amber |
| `nexusError` | #C44536 | Errors - brick red |

### Backgrounds
- **Light mode**: Warm cream (#E4D5C3) page background, white cards
- **Dark mode**: System dark backgrounds

### Typography
- System SF fonts
- Large titles for navigation
- Rounded number displays for metrics

### Components
- Cards with 16px corner radius, subtle shadows
- Chips/badges for status indicators
- Glass-effect cards (ultraThinMaterial)
- Animated number transitions
- Haptic feedback on key actions

---

## Tab Bar Structure (5 tabs)

### Tab 1: Home (house icon)
**Purpose**: Daily dashboard - the "command center" showing today's status at a glance.

**Sections (scrollable):**
1. **Status Banners** (conditional)
   - Offline mode indicator
   - Syncing indicator with pending count
   - Cached data indicator with age
   - Stale data warning with refresh button

2. **Meal Confirmation Card** (if pending)
   - AI-inferred meal from location/time
   - Confirm or skip buttons

3. **Daily Briefing Card** ("ExplainToday")
   - Natural language summary of the day
   - Data gaps highlighted
   - e.g., "Recovery 72% (good). Spent 45 AED, 30% below average. No sleep data yet."

4. **Status Card** (main hero)
   - Recovery ring (0-100%, color-coded)
   - Sleep duration
   - Today's spend with comparison to 7-day average
   - Workout count and minutes
   - Reminder summary (X due today, Y overdue)

5. **Streak Badges Row**
   - Horizontal scroll of achievement badges
   - Water streak, logging streak, etc.

6. **Nutrition Card**
   - Calories consumed
   - Meals logged count
   - Water intake (ml)

7. **Fasting Card**
   - Active fast timer (HH:MM elapsed)
   - Start/Break fast button
   - Goal progress badges (16h, 18h, 20h)

8. **Home Status Card**
   - Smart home summary (lights on, vacuum status)
   - Tap to open Home Assistant

9. **Music Card**
   - Currently/recently played track
   - Listening minutes today

10. **Mood Card**
    - Today's mood and energy scores
    - Trend indicator

11. **Medications Card**
    - Today's medication doses from HealthKit

12. **Insights Section**
    - AI-generated insights (up to 3)
    - e.g., "Unusual spending pattern detected"

**Toolbar:**
- Quick Log button (+) opens logging sheet

---

### Tab 2: Health (heart icon)
**Purpose**: Health metrics, trends, and insights from WHOOP + HealthKit.

**Layout**: Single scrollable view with sections:

1. **Today Section**
   - Recovery score ring
   - HRV value
   - Resting heart rate
   - Sleep performance percentage
   - Strain score
   - Steps count

2. **Trends Section**
   - Period selector (7d / 30d / 90d)
   - Charts for:
     - Recovery over time
     - HRV trend
     - Sleep duration trend
     - Weight trend
   - Sparkline mini-charts

3. **Insights Section**
   - AI-generated health observations
   - Correlations and recommendations

---

### Tab 3: Finance (chart.pie icon)
**Purpose**: Spending tracking, budgets, and financial planning.

**Layout**: Scrollable with navigation links:

1. **Overview Section**
   - Monthly spend total
   - Category breakdown (pie or bar chart)
   - Budget status indicators
   - Comparison to previous period
   - Recent transactions list (last 5)

2. **Navigation Links**
   - "All Transactions" → Full transaction list with filters
   - "Finance Settings" → Planning view

**Add Expense/Income**: Sheet modals

**Transaction Detail**: Shows full transaction with:
- Amount, date, merchant
- Category (changeable)
- Notes
- Linked receipt (if any)

**Finance Planning View** (Settings gear):
- Categories management
- Budgets configuration
- Recurring items (subscriptions, income)
- Auto-categorization rules

---

### Tab 4: Calendar (calendar.circle icon)
**Purpose**: Event management synced with Apple Calendar.

**Layout**:
1. **Month Header**
   - Month/Year display
   - Previous/Next month buttons
   - "Today" button

2. **Calendar Grid**
   - 7-column week layout
   - Day cells with event dots
   - Selected day highlighted

3. **Selected Day Detail**
   - List of events for selected date
   - Tap event for detail sheet

**Event Creation/Edit**: Sheet with:
- Title, location, notes
- Start/end date-time
- All-day toggle
- Calendar selection

---

### Tab 5: More (ellipsis.circle icon)
**Purpose**: Secondary features and settings.

**Sections (List style):**

1. **Life Data**
   - Documents (passports, visas, IDs with expiry tracking)
   - Receipts (grocery receipts with nutrition linking)
   - Music (listening history and stats)
   - Notes (Obsidian vault search)
   - Reminders (tasks synced with Apple Reminders)
   - Medications (HealthKit data)
   - Supplements (daily tracking)
   - Workouts (activity log)

2. **Wellness**
   - Water (hydration tracking)
   - Mood & Energy (logging and history)

3. **Home**
   - Home Control (lights, vacuum, camera via Home Assistant)

4. **App**
   - Pipeline Health (data feed status)
   - Settings (connection, sync, data sources)

---

## Key Flows

### Quick Log (FAB on Home tab)
Sheet with:
- Text/voice input field
- Mic button for speech-to-text
- Quick action grid:
  - Log Food → Food logging view
  - Water → Water log view
  - Coffee (one-tap)
  - Snack (one-tap)
  - Weight (prefills input)
- Submit button

### Food Logging
1. Meal type selector (Breakfast, Lunch, Dinner, Snack)
2. Text description or voice input
3. Optional: Photo capture for AI analysis
4. Optional: Barcode scanner
5. Food search (2.4M foods database)
6. Portion/quantity adjustment
7. Macro display before logging

### Water Logging
- Quick add buttons (250ml, 500ml, 750ml)
- Custom amount input
- Daily total display with goal progress

### Fasting
- Start/Break fast toggle
- Elapsed time display (live updating)
- Goal checkpoints (12h, 16h, 18h, 20h)
- History view

---

## Data States

Each view handles:
1. **Loading**: Skeleton/shimmer or spinner
2. **Empty**: Illustration + message + action button
3. **Error**: Error message + retry button
4. **Offline**: Banner indicating offline mode, queued items count
5. **Stale**: Warning banner with refresh option

---

## Widgets (iOS Home Screen)

1. **Water Widget** (Small)
   - Today's water total
   - Tap to log 250ml

2. **Daily Summary Widget** (Medium/Large)
   - Calories, protein, water, weight

3. **Recovery Widget** (Small/Circular/Rectangular)
   - WHOOP recovery score ring
   - HRV and RHR values

---

## Siri Integration

Voice commands via App Intents:
- "Log food in Nexus" → prompts for description
- "Log breakfast/lunch/dinner in Nexus"
- "Log water in Nexus" → logs 250ml
- "Log mood in Nexus" → prompts for score
- "Start fast in Nexus"
- "Break fast in Nexus"

---

## Notifications

- Meal confirmation requests
- Document expiry reminders
- Sync failure alerts
- Fasting goal achievements

---

## Design Opportunities for Redesign

### Current Pain Points
1. Dense information on Home tab
2. Inconsistent card styles
3. Limited use of haptics (only 2 views)
4. No keyboard shortcuts for iPad
5. Widgets don't fetch real data

### Suggested Improvements
1. **Live Activities**: Fasting timer on lock screen
2. **Haptic feedback**: On all toggle actions
3. **Keyboard shortcuts**: For power users on iPad
4. **Consistent color system**: Replace system colors with theme
5. **Micro-animations**: Staggered list reveals
6. **Focus states**: Better accessibility
7. **Deep links**: Quick actions from widgets/notifications

---

## Technical Notes for Designer

- **iOS 17+** required
- SwiftUI native (no UIKit)
- Dark mode fully supported
- Dynamic Type supported
- VoiceOver accessibility labels implemented
- Pull-to-refresh on all data views
- Background refresh for widgets

---

## File Deliverables Needed

1. **Tab icons** (filled/unfilled states)
2. **Card components** (all states)
3. **Chart styles** (line, bar, ring)
4. **Empty states** (illustrations)
5. **Loading states** (skeleton patterns)
6. **Widget designs** (all sizes)
7. **Siri response screens**
8. **Notification designs**
