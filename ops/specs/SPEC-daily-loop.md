# Daily Loop: Evening Review + Morning Briefing

## Overview

Create a **daily habit loop** that:
1. **Evening Review** (8-10 PM): Quick subjective check-in (mood, energy, wins)
2. **Morning Briefing** (wake-up): Personalized daily preview based on all data

This unlocks **cross-domain correlations** (sleep → mood, recovery → productivity) and makes the app a daily habit.

---

## Part 1: Evening Review

### Purpose
- Capture subjective data not available from sensors (mood, energy, reflection)
- Confirm/correct any pending inferences (meals, transactions)
- Close the day with intention

### User Experience

**Trigger options:**
1. Push notification at 8 PM (configurable): "How was your day?"
2. Manual via TodayView card if not yet logged
3. Widget tap (future)

**Flow (3 screens, <60 seconds total):**

```
┌─────────────────────────────────────────┐
│         Evening Review                   │
│         Thursday, Feb 6                  │
├─────────────────────────────────────────┤
│                                         │
│  How are you feeling?                   │
│                                         │
│  😫  😕  😐  🙂  😊                      │
│   1   2   3   4   5                     │
│                                         │
│  Energy level?                          │
│                                         │
│  ○ ○ ○ ○ ○                              │
│  1 2 3 4 5                              │
│                                         │
│  [Next →]                               │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│         Quick Confirmations             │
├─────────────────────────────────────────┤
│                                         │
│  Meals detected:                        │
│  ┌───────────────────────────────────┐  │
│  │ 🍽️ Lunch at Carrefour (12:34)    │  │
│  │ Carrefour receipt AED 47         ✓│  │
│  └───────────────────────────────────┘  │
│                                         │
│  Unconfirmed:                           │
│  ┌───────────────────────────────────┐  │
│  │ ❓ Dinner (~7 PM)                 │  │
│  │ [Ate out] [Home] [Skipped]       │  │
│  └───────────────────────────────────┘  │
│                                         │
│  [Next →]                               │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│         Day Complete ✓                  │
├─────────────────────────────────────────┤
│                                         │
│  Today's win (optional):                │
│  ┌───────────────────────────────────┐  │
│  │ Got 10k steps despite busy day   │  │
│  └───────────────────────────────────┘  │
│                                         │
│  Any notes?                             │
│  ┌───────────────────────────────────┐  │
│  │ Stressful meeting, skipped gym   │  │
│  └───────────────────────────────────┘  │
│                                         │
│  [Done ✓]                               │
│                                         │
│  ───────────────────────────────────    │
│  Tomorrow: 4 meetings, recovery 72%     │
│  💡 Consider light workout              │
└─────────────────────────────────────────┘
```

### Data Model

**New table: `life.daily_reviews`**

```sql
CREATE TABLE life.daily_reviews (
    id              SERIAL PRIMARY KEY,
    day_date        DATE NOT NULL UNIQUE,
    mood_score      INT CHECK (mood_score BETWEEN 1 AND 5),
    energy_score    INT CHECK (energy_score BETWEEN 1 AND 5),
    win_text        TEXT,
    notes           TEXT,
    meals_confirmed JSONB,  -- [{time, type, confirmed_as}]
    logged_at       TIMESTAMPTZ DEFAULT NOW(),
    source          TEXT DEFAULT 'ios'
);

CREATE INDEX idx_daily_reviews_day ON life.daily_reviews (day_date DESC);

GRANT SELECT, INSERT, UPDATE ON life.daily_reviews TO nexus;
GRANT USAGE, SELECT ON SEQUENCE life.daily_reviews_id_seq TO nexus;
```

**Add to `life.daily_facts`:**

```sql
ALTER TABLE life.daily_facts
ADD COLUMN mood_score INT,
ADD COLUMN energy_score INT;
```

### n8n Webhook

**POST `/webhook/nexus-evening-review`**

```json
{
  "date": "2026-02-06",
  "mood_score": 4,
  "energy_score": 3,
  "win_text": "Got 10k steps despite busy day",
  "notes": "Stressful meeting, skipped gym",
  "meals_confirmed": [
    {"time": "12:34", "type": "lunch", "confirmed_as": "grocery_receipt"},
    {"time": "19:00", "type": "dinner", "confirmed_as": "skipped"}
  ]
}
```

**Response:**
```json
{
  "success": true,
  "streak": 5,
  "tomorrow_preview": {
    "meetings": 4,
    "recovery": 72,
    "suggestion": "Consider light workout"
  }
}
```

### iOS Implementation

**Files to create:**
- `ios/Nexus/Views/Review/EveningReviewView.swift` — Main flow (3 pages)
- `ios/Nexus/Views/Review/MoodEnergyPicker.swift` — Reusable rating component
- `ios/Nexus/Models/ReviewModels.swift` — Data models

**Files to modify:**
- `ios/Nexus/Views/Dashboard/TodayView.swift` — Add "Evening Review" card if not done today
- `ios/Nexus/Services/NexusAPI.swift` — Add `submitEveningReview()` endpoint
- `ios/Nexus/Models/DashboardPayload.swift` — Add `eveningReviewStatus`
- `ios/Nexus/Services/NotificationManager.swift` — Add evening review notification

**Dashboard card (appears after 8 PM if not reviewed):**

```swift
struct EveningReviewCard: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Evening Review")
                    .font(.headline)
                Text("How was your day?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Start") { ... }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}
```

---

## Part 2: Morning Briefing

### Purpose
- Single glance at the day ahead
- Recovery-adjusted recommendations
- Surface what matters today

### User Experience

**Trigger:**
- Appears at top of TodayView in the morning (before noon)
- Replaces current status card temporarily (or sits above it)
- Dismissable after viewing

**Design:**

```
┌─────────────────────────────────────────┐
│  ☀️ Good morning, Arafa                 │
│  Thursday, February 6                    │
├─────────────────────────────────────────┤
│                                         │
│  RECOVERY        SLEEP        BUDGET    │
│    72%          7h 12m      AED 847     │
│    🟡 avg         ✓          ✓ on track │
│                                         │
├─────────────────────────────────────────┤
│                                         │
│  📅 Today                               │
│  • 4 meetings (3h 30m total)            │
│  • 2 reminders due                      │
│  • Leg day (scheduled workout)          │
│                                         │
├─────────────────────────────────────────┤
│                                         │
│  💡 Based on 72% recovery:              │
│  "Moderate intensity today. Your HRV    │
│   is 12% below baseline."               │
│                                         │
├─────────────────────────────────────────┤
│                                         │
│  📊 Yesterday                           │
│  Mood: 😊 (4)  Energy: 3                │
│  Spent: AED 127  Steps: 8,432           │
│                                         │
│  [Dismiss]                [Details →]   │
└─────────────────────────────────────────┘
```

### Data Sources (already available)

| Section | Source |
|---------|--------|
| Recovery/Sleep/Budget | `DashboardPayload.todayFacts` |
| Calendar | `DashboardPayload.calendarSummary` |
| Reminders | `DashboardPayload.reminderSummary` |
| Yesterday's review | New: `daily_reviews` table |
| Recommendations | New: computed from correlations |

### Recommendation Engine (v1)

Simple rule-based system stored in database:

```sql
CREATE TABLE life.briefing_rules (
    id              SERIAL PRIMARY KEY,
    condition_sql   TEXT NOT NULL,
    message         TEXT NOT NULL,
    priority        INT DEFAULT 50,
    active          BOOLEAN DEFAULT true
);

-- Example rules:
INSERT INTO life.briefing_rules (condition_sql, message, priority) VALUES
('recovery_score < 50', 'Low recovery. Consider rest day or light activity.', 100),
('recovery_score BETWEEN 50 AND 70 AND strain > 10', 'Moderate recovery but yesterday was intense. Active recovery suggested.', 80),
('sleep_hours < 6', 'Short sleep. Watch caffeine after 2 PM, consider early bedtime.', 90),
('spend_total > spend_7d_avg * 1.5', 'Spending trending high. You''ve spent {{spend_total}} vs {{spend_7d_avg}} avg.', 70),
('meals_logged = 0 AND EXTRACT(HOUR FROM NOW() AT TIME ZONE ''Asia/Dubai'') > 12', 'No meals logged yet. Remember to track lunch!', 60),
('mood_score <= 2 AND recovery_score < 60', 'Yesterday was tough. Be gentle with yourself today.', 85);
```

**Backend function:**

```sql
CREATE OR REPLACE FUNCTION life.get_morning_briefing(p_date DATE DEFAULT CURRENT_DATE)
RETURNS JSONB AS $$
DECLARE
    v_facts RECORD;
    v_yesterday_review RECORD;
    v_calendar JSONB;
    v_recommendations JSONB;
BEGIN
    -- Get today's facts
    SELECT * INTO v_facts FROM life.daily_facts WHERE day = p_date;

    -- Get yesterday's review
    SELECT * INTO v_yesterday_review FROM life.daily_reviews WHERE day_date = p_date - 1;

    -- Get calendar summary
    SELECT jsonb_build_object(
        'meeting_count', COUNT(*) FILTER (WHERE event_type = 'meeting'),
        'total_minutes', SUM(duration_minutes)
    ) INTO v_calendar
    FROM raw.calendar_events
    WHERE DATE(start_time AT TIME ZONE 'Asia/Dubai') = p_date;

    -- Get applicable recommendations
    SELECT jsonb_agg(jsonb_build_object('message', message, 'priority', priority))
    INTO v_recommendations
    FROM life.briefing_rules
    WHERE active = true
    -- Dynamic evaluation would happen in application layer
    ORDER BY priority DESC
    LIMIT 3;

    RETURN jsonb_build_object(
        'date', p_date,
        'greeting', CASE
            WHEN EXTRACT(HOUR FROM NOW() AT TIME ZONE 'Asia/Dubai') < 12 THEN 'Good morning'
            WHEN EXTRACT(HOUR FROM NOW() AT TIME ZONE 'Asia/Dubai') < 17 THEN 'Good afternoon'
            ELSE 'Good evening'
        END,
        'today', jsonb_build_object(
            'recovery_score', v_facts.recovery_score,
            'sleep_hours', v_facts.sleep_hours,
            'budget_remaining', 5000 - COALESCE(v_facts.spend_total, 0), -- TODO: real budget
            'calendar', v_calendar
        ),
        'yesterday', CASE WHEN v_yesterday_review IS NOT NULL THEN jsonb_build_object(
            'mood_score', v_yesterday_review.mood_score,
            'energy_score', v_yesterday_review.energy_score,
            'spend_total', (SELECT spend_total FROM life.daily_facts WHERE day = p_date - 1),
            'steps', (SELECT steps FROM life.daily_facts WHERE day = p_date - 1)
        ) ELSE NULL END,
        'recommendations', v_recommendations
    );
END;
$$ LANGUAGE plpgsql;
```

### n8n Webhook

**GET `/webhook/nexus-morning-briefing`**

```json
{
  "success": true,
  "briefing": {
    "date": "2026-02-06",
    "greeting": "Good morning",
    "today": {
      "recovery_score": 72,
      "sleep_hours": 7.2,
      "budget_remaining": 847,
      "calendar": {
        "meeting_count": 4,
        "total_minutes": 210
      },
      "reminders_due": 2
    },
    "yesterday": {
      "mood_score": 4,
      "energy_score": 3,
      "spend_total": 127,
      "steps": 8432
    },
    "recommendations": [
      {"message": "Moderate intensity today. HRV 12% below baseline.", "priority": 80}
    ]
  }
}
```

### iOS Implementation

**Files to create:**
- `ios/Nexus/Views/Dashboard/MorningBriefingView.swift` — Briefing card

**Files to modify:**
- `ios/Nexus/Views/Dashboard/TodayView.swift` — Show briefing at top
- `ios/Nexus/Models/DashboardPayload.swift` — Add `morningBriefing` field
- `ios/Nexus/Services/NexusAPI.swift` — Add `fetchMorningBriefing()` (or include in dashboard payload)

**Dismissal logic:**
- Store `lastBriefingDismissedDate` in UserDefaults
- Only show if it's before noon AND not dismissed today

---

## Part 3: Correlation Insights (Future Enhancement)

Once we have mood/energy data, enable cross-domain insights:

**New table: `life.correlations`**

```sql
CREATE TABLE life.correlations (
    id              SERIAL PRIMARY KEY,
    metric_a        TEXT NOT NULL,  -- 'sleep_hours'
    metric_b        TEXT NOT NULL,  -- 'mood_score'
    correlation     NUMERIC(4,3),   -- -1.0 to 1.0
    sample_size     INT,
    computed_at     TIMESTAMPTZ DEFAULT NOW(),
    insight_text    TEXT            -- "Better sleep → higher mood (r=0.72)"
);

-- Nightly job computes correlations
CREATE OR REPLACE FUNCTION life.compute_correlations()
RETURNS void AS $$
BEGIN
    -- Sleep → Mood
    INSERT INTO life.correlations (metric_a, metric_b, correlation, sample_size, insight_text)
    SELECT
        'sleep_hours', 'mood_score',
        CORR(df.sleep_hours, dr.mood_score),
        COUNT(*),
        CASE
            WHEN CORR(df.sleep_hours, dr.mood_score) > 0.5 THEN 'Better sleep strongly correlates with higher mood'
            WHEN CORR(df.sleep_hours, dr.mood_score) > 0.3 THEN 'Sleep quality moderately affects your mood'
            ELSE 'Sleep and mood show weak correlation for you'
        END
    FROM life.daily_facts df
    JOIN life.daily_reviews dr ON dr.day_date = df.day
    WHERE df.sleep_hours IS NOT NULL AND dr.mood_score IS NOT NULL
    ON CONFLICT DO NOTHING;

    -- Recovery → Next-day spending
    -- ... more correlations
END;
$$ LANGUAGE plpgsql;
```

---

## Implementation Order

### Phase 1: Evening Review (MVP)
1. Migration: `life.daily_reviews` table
2. n8n webhook: POST evening review
3. iOS: EveningReviewView (simple 2-screen flow)
4. iOS: TodayView card after 8 PM
5. Notification: 8 PM reminder

**Estimated effort:** 1-2 sessions

### Phase 2: Morning Briefing
1. Migration: Add mood/energy to daily_facts (trigger from reviews)
2. Migration: `life.briefing_rules` table with seed data
3. n8n webhook: GET morning briefing
4. iOS: MorningBriefingView card
5. iOS: Dismiss logic

**Estimated effort:** 1-2 sessions

### Phase 3: Enhancements
1. Correlation engine
2. Widget for mood/energy quick log
3. Siri intent: "Log my mood"
4. Evening review notification with preview

**Estimated effort:** 2-3 sessions

---

## Files Summary

### New Files
| File | Purpose |
|------|---------|
| `backend/migrations/XXX_daily_reviews.up.sql` | Evening review table |
| `backend/migrations/XXX_morning_briefing.up.sql` | Briefing rules + function |
| `backend/n8n-workflows/evening-review-webhook.json` | Submit review |
| `backend/n8n-workflows/morning-briefing-webhook.json` | Get briefing |
| `ios/Nexus/Views/Review/EveningReviewView.swift` | Review flow |
| `ios/Nexus/Views/Review/MoodEnergyPicker.swift` | Rating component |
| `ios/Nexus/Views/Dashboard/MorningBriefingView.swift` | Briefing card |
| `ios/Nexus/Models/ReviewModels.swift` | Data models |

### Modified Files
| File | Change |
|------|--------|
| `ios/Nexus/Views/Dashboard/TodayView.swift` | Add review card + briefing |
| `ios/Nexus/Services/NexusAPI.swift` | Add review + briefing endpoints |
| `ios/Nexus/Services/NotificationManager.swift` | Add evening notification |
| `ios/Nexus/Models/DashboardPayload.swift` | Add review status + briefing |

---

## Success Metrics

1. **Engagement**: >50% daily completion of evening review after 2 weeks
2. **Data quality**: Mood/energy logged for >80% of days
3. **Insight value**: At least 2 actionable correlations discovered in first month
4. **Habit formation**: User opens app in morning to see briefing

---

## Open Questions

1. Should evening review be blocking (modal) or optional (card)?
2. Include yesterday's spending in evening review summary?
3. How aggressive should evening notification be? (configurable?)
4. Should morning briefing auto-dismiss at noon or persist as collapsed card?
