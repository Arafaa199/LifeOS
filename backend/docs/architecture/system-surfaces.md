# LifeOS System Surfaces — Architecture Plan

This document defines **all user-facing surfaces** of LifeOS beyond the main app UI:
widgets, notifications, live activities, Siri/Shortcuts, and system integrations.

Goals:
- Make LifeOS feel *ambient* and *always present*
- Avoid notification fatigue
- Ensure all surfaces are **data-coherent**, **low-latency**, and **offline-safe**
- Provide a clear expansion path without architectural debt

---

## 1. Surface Inventory

| Surface | Purpose | Data Source | Update Frequency |
|-------|--------|------------|------------------|
| Home Widget (Small) | Recovery score + single metric | `daily_facts.recovery_score` | Hourly (timeline) |
| Home Widget (Medium) | Recovery + Sleep + Spend status | `daily_facts` | Hourly |
| Home Widget (Large) | Full daily snapshot | `daily_facts` | Hourly |
| Lock Screen Widget (Circular) | Recovery score gauge | `daily_facts.recovery_score` | Hourly |
| Lock Screen Widget (Rectangular) | Fasting timer / hours since meal | `fasting.elapsed_hours` | 15 min |
| Lock Screen Widget (Inline) | “72% · 7h · AED 150” | `daily_facts` | Hourly |
| Live Activity | Active fasting countdown | `fasting.started_at` | 1 min |
| Live Activity | Document expiry countdown (48h) | `documents.expires_at` | Hourly |
| Notifications | Event-based alerts | Various | Event-driven |
| Siri / App Intents | Voice logging + queries | Write-only | Instant |
| Shortcuts | Automation hooks | Write-only | Instant |
| Focus Modes | Notification suppression | Device state | Automatic |

---

## 2. Notification Policy

### Allowed Triggers

| Event | Priority | Frequency Cap | Suppression |
|-----|---------|---------------|-------------|
| Document expires in 7 days | Normal | Once per document | None |
| Document expires in 48h | **Critical** | Once | None |
| Document expired | **Critical** | Once | None |
| Medication missed (2h late) | **Critical** | Once per dose | Sleep Focus |
| Spend anomaly (>3σ) | Normal | Max 1/day | Work Focus |
| Fasting milestone (16h / 18h / 20h) | Normal | Once per milestone | Sleep Focus |
| Weekly summary ready | Normal | Once/week | None |
| Data gap detected (>24h no sync) | Normal | Once per gap | Work Focus |

### Hard Rules
- No notifications for routine data ingestion
- No duplicate notifications for the same event
- No notifications if the same info is visible in a widget
- **Critical** → sound + vibration + bypass Focus  
- **Normal** → silent + badge only
- Every notification must be actionable or informative

### Focus Suppression Matrix

| Focus Mode | Suppress Normal | Suppress Critical |
|-----------|-----------------|-------------------|
| Sleep | Yes | No (meds only) |
| Work | Yes | No |
| Personal | No | No |
| Do Not Disturb | Yes | No |

---

## 3. Live Activity Candidates

### Supported

| Activity | Start Trigger | End Trigger | Display |
|--------|--------------|-------------|---------|
| Fasting Session | User taps “Start Fast” | Break fast / 24h elapsed | Elapsed time + progress ring |
| Document Expiry | 48h before expiry | Renewed / expired | “Visa expires in 1d 14h” |

### Not Supported
- Recovery score (static intraday)
- Spend tracking (no urgency)
- Sleep (already completed)

---

## 4. Widget Roadmap

### Home Screen Widgets

| Size | Content | Priority |
|----|--------|----------|
| Small | Recovery ring + score | P0 |
| Medium | Recovery + Sleep + Spend | P1 |
| Large | Full daily snapshot | P2 |

### Lock Screen Widgets

| Type | Content | Priority |
|----|--------|----------|
| Circular | Recovery gauge | P0 |
| Rectangular | Fasting elapsed / since meal | P0 |
| Inline | “72% · 7h · AED 85” | P1 |

### Data Binding Rules
- Widgets read from **App Group shared container**
- App writes `daily_facts.json` after sync
- Widgets **never** perform network calls
- Data older than 2h shows as “stale”

---

## 5. Siri & Shortcuts

### Existing
- Log water
- Log mood
- Log weight
- Start fast
- Break fast

### New Intents

| Intent | Example Phrase | Action |
|------|----------------|--------|
| LogMedicationIntent | “I took my vitamins” | Log medication |
| SkipMedicationIntent | “Skip my meds” | Mark skipped |
| QuickExpenseIntent | “I spent 50 dirhams on coffee” | NL → transaction |
| CheckRecoveryIntent | “What’s my recovery?” | Spoken summary |
| CheckSpendIntent | “How much did I spend today?” | Spoken summary |

### Shortcut Automations

| Trigger | Action |
|-------|--------|
| Wake alarm dismissed | HealthKit sync |
| Arrive home | Log location event |
| Leave home | Log location event |
| CarPlay connected | Suppress non-critical notifications |
| Low Power Mode | Reduce refresh cadence |

---

## 6. Implementation Order

| Rank | Surface | Impact | Effort |
|----|--------|--------|--------|
| 1 | Lock Screen Circular (Recovery) | High | Low |
| 2 | Lock Screen Rectangular (Fasting) | High | Low |
| 3 | Home Widget Small | High | Low |
| 4 | Live Activity (Fasting) | High | Medium |
| 5 | Home Widget Medium | Medium | Medium |
| 6 | Critical Doc Notifications | High | Low |
| 7 | Siri Read Commands | Medium | Low |
| 8 | Home Widget Large | Medium | High |
| 9 | Live Activity (Documents) | Low | Medium |
| 10 | Focus Mode Integration | Low | Medium |

---

## 7. Anti-Patterns (Do Not Build)

- Widgets with input actions
- Notifications for every transaction
- Motivational or “cheerleading” alerts
- Hourly fasting notifications
- Widgets that fetch network data
- Live Activities for static metrics
- Charts in widgets
- WebView notification links
- Duplicate notifications for same event

---

## 8. Recommended Starting Point

### Lock Screen Circular Widget — Recovery Score

**Why**
- Highest visibility
- Single metric
- Minimal code
- No network calls
- Foundation for all future widgets

**First Implementation Steps**
1. Create Widget Extension target
2. Configure App Group (`group.com.nexus.shared`)
3. Persist `daily_facts` snapshot after sync
4. Implement `RecoveryWidgetProvider`
5. Render circular gauge:
   - Green > 66
   - Yellow 34–66
   - Red < 34

---

## 9. Guiding Principle

> LifeOS should feel like *infrastructure*, not an app.  
> Information appears when needed, disappears when not, and never nags.
