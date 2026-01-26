# ADL: Assisted Capture Phase

**Status:** DOCUMENTED (not implemented)
**Created:** 2026-01-25
**Purpose:** Plan frictionless data capture via iPhone camera and Apple Watch

---

## Context

LifeOS meal inference works but requires user confirmation via iOS app.
Goal: Reduce friction to near-zero while maintaining data accuracy.

---

## iPhone Camera Meal Confirmation Flow

### Concept

When user takes a photo of food:
1. iOS detects food photo (ML classification)
2. Prompt: "Log this meal?" (Yes / No)
3. If Yes: Match to pending inferred meal OR create new entry
4. Photo stored as evidence (optional)

### Technical Requirements

- [ ] Core ML model for food detection (on-device)
- [ ] Photo intent handler (share sheet or camera roll watcher)
- [ ] Matching logic: photo timestamp ↔ inferred meal time (±2 hours)
- [ ] Fallback: Manual meal type selection if no match

### UX Flow

```
[User takes photo of meal]
        ↓
[iOS detects food in photo]
        ↓
[Notification: "Log lunch?"]
        ↓
    [Yes]           [No]
      ↓               ↓
[Match to pending] [Dismiss]
      ↓
[Confirmed in DB]
```

### Privacy Considerations

- Photos processed on-device only
- Photo storage is OPT-IN
- No cloud ML for food detection

---

## Apple Watch Micro-Actions (Max 3)

### Principle

Watch interactions must be completable in <3 seconds.
No text input. No scrolling. Binary choices only.

### Action 1: Meal Confirmation

**Trigger:** Complication tap OR notification
**Display:** "Lunch at 12:30?"
**Actions:** ✓ (confirm) | ✗ (skip)
**Haptic:** Success/failure feedback

### Action 2: Water Log

**Trigger:** Complication tap
**Display:** Current water count + glass icon
**Action:** Single tap = +250ml
**Haptic:** Subtle confirmation

### Action 3: Quick Mood

**Trigger:** End-of-day notification (20:00)
**Display:** 5 emoji faces (1-5 scale)
**Action:** Tap face to log
**Haptic:** Confirmation

### NOT Included (Too Complex for Watch)

- Expense logging (requires amount input)
- Food logging (requires description)
- Transaction review (requires scrolling)

---

## Implementation Order (When Approved)

1. **Watch Meal Confirmation** — Highest impact, simplest implementation
2. **Watch Water Log** — Simple increment action
3. **iPhone Camera Flow** — Requires ML model, more complex
4. **Watch Quick Mood** — Nice-to-have, lowest priority

---

## Dependencies

- WatchKit app scaffold
- Watch ↔ iPhone communication (WatchConnectivity)
- Core ML food classification model (Apple's CreateML or pre-trained)
- Background photo analysis capability

---

## Success Metrics

- Meal confirmation rate: >80% within 24h
- Water logging frequency: >4 entries/day
- Time-to-confirm: <3 seconds on Watch

---

## Risks

| Risk | Mitigation |
|------|------------|
| False positive food detection | Require user confirmation, don't auto-log |
| Watch battery drain | Minimize background processing |
| Sync failures | Queue actions locally, sync when connected |

---

## Status

**DO NOT IMPLEMENT** until:
1. Observation window complete (2026-02-01)
2. Post-usage queue reviewed
3. Human approval granted

This document is for planning only.
