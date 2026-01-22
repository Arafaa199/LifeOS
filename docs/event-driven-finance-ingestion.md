# Event-Driven Finance Ingestion - Design Note

## Current State Assessment

### Q1: Current Trigger for Salary/Bank Messages

**Already event-driven + scheduled fallback:**

| Component | Trigger | Mechanism |
|-----------|---------|-----------|
| `com.nexus.sms-watcher` | Real-time | `fswatch` on `~/Library/Messages/chat.db` |
| `com.nexus.sms-import` | Every 15 min | launchd StartInterval (safety net) |

When an SMS arrives → fswatch detects chat.db change → `import-sms-transactions.js` runs within seconds.

### Q2: Supported Sources

| Source | Status | Banks/Vendors |
|--------|--------|---------------|
| **SMS** | ✅ Event-driven | Emirates NBD, AlRajhi, Jordan Kuwait Bank |
| **Email (receipts)** | ⏳ Manual | Carrefour UAE (Gmail label monitored) |
| **BNPL** | ✅ Via SMS | Tabby installment tracking |

### Q3: Gap Analysis

**SMS ingestion is already event-driven.** The only manual component is Gmail receipt ingestion (`./receipt_ingestion.py --fetch`).

---

## Proposed Enhancement: Event-Driven Gmail Receipts

### Option A: launchd Scheduler (Recommended)
**Smallest change - 1 new plist file**

```xml
<!-- com.nexus.receipt-ingest.plist -->
<key>StartInterval</key>
<integer>3600</integer>  <!-- Hourly check -->
<key>ProgramArguments</key>
<array>
  <string>/path/to/receipt-ingest/run-receipt-ingest.sh</string>
  <string>--fetch</string>
  <string>--parse</string>
</array>
```

**Pros:** Simple, consistent with existing SMS architecture
**Cons:** Up to 1-hour latency for new receipts

### Option B: Gmail Push Notifications (Cloud Pub/Sub)
**True real-time but requires GCP setup**

1. Create GCP Pub/Sub topic
2. Configure Gmail API watch on label `LifeOS/Receipts/Carrefour`
3. n8n webhook receives push notification
4. Triggers `receipt_ingestion.py --fetch --parse`

**Pros:** Immediate ingestion
**Cons:** Requires GCP project, more moving parts

### Option C: iPhone Shortcuts + Webhooks (Secondary)
For SMS from iPhone (when macOS Messages sync fails):

1. iOS Shortcut triggers on SMS from bank
2. Sends POST to n8n webhook with SMS body
3. n8n parses and inserts transaction

**Pros:** Works when laptop is off
**Cons:** Requires iOS automation setup

---

## Decision: Option A (Hourly launchd)

**Rationale:**
- Receipts are not time-critical (daily reconciliation is sufficient)
- Matches existing architecture (SMS watcher pattern)
- Zero cloud dependencies
- Easy to upgrade to Option B later if needed

**Implementation:** Single plist file, 30 minutes of work

---

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────┐
│                    EVENT-DRIVEN LAYER                       │
├──────────────────────┬──────────────────────────────────────┤
│  SMS (real-time)     │  Gmail Receipts (hourly)            │
│  ├─ fswatch chat.db  │  ├─ launchd StartInterval           │
│  ├─ import-sms.js    │  ├─ receipt_ingestion.py --fetch    │
│  └─ 3 banks          │  └─ Carrefour UAE                   │
└──────────────────────┴──────────────────────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │   PostgreSQL     │
                    │   nexus.finance  │
                    └──────────────────┘
```

---

*Created: 2026-01-22*
