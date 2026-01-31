# INCIDENT: Data Trust & Freshness — 2026-01-30

## Status: RESOLVED

## Resolution Summary (Jan 30 2026, 11:36 Dubai)

| Fix | Status | Evidence |
|-----|--------|----------|
| SMS body extraction (attributedBody) | DONE | 43 msgs extracted, 12 new tx imported |
| SMS pattern fixes (AED, EmiratesNBD EN) | DONE | 1 unmatched down from 283 |
| Backfill 30 days | DONE | 275 SMS tx total, 44 in 30d |
| Replay idempotency | VERIFIED | Pre=Post: 275 tx, -4192.65 total |
| WHOOP feed triggers | VERIFIED | 3 triggers correct (migration 091 applied) |
| Email receipts | VERIFIED | Pipeline healthy, no new emails since Jan 27 |
| BNPL Tabby matching | DONE | Amazon.ae plan 2/4, tx 6847 linked |
| iOS Pipeline Health screen | DONE | New section in SettingsView, build passes |
| Pool/arg fixes | DONE | max:3 pool, --days= arg parsing |

## Root Cause Summary

Six distinct pipeline failures, each with a different root cause:

| Pipeline | Root Cause | Impact |
|----------|-----------|--------|
| SMS Finance | `import-sms-transactions.js` reads `m.text` which is NULL on modern iOS; bodies are in `m.attributedBody` (NSAttributedString blob) | **0 SMS ingested in 6+ days**. 15+ AlRajhi transactions missing. |
| Weight/HealthKit | Pipeline works. Data in DB and API. | **False alarm** — weight_kg=110.3 returns correctly from API. |
| WHOOP Direct Sync | OAuth token rotation + parallel fan-out bug (fixed prev session). Sleep/strain still stale — only recovery writes via Direct Sync, sleep/strain lag by design (WHOOP API returns latest only, cycle not yet closed). | Today's recovery=NULL (cycle not closed), yesterday=85. Sleep/strain only from old HA pipeline (last: Jan 29). |
| Email Receipts | Gmail automation ran Jan 27. No new receipts since. Need to verify if new emails exist and if cron is firing. | Last receipt: Jan 27 Carrefour. |
| Tabby/BNPL | No BNPL data model exists. AlRajhi SMS shows AED 1244.14 charge to "Tabby, 800 82229" — this is a BNPL total being charged as single transaction. | Incorrect spend amount in dashboard. |
| Dashboard API | Works correctly. `dashboard.get_payload()` returns weight, feed_status, stale_feeds. | **False alarm** — earlier test used wrong API key. |

## Per-Pipeline Trace

### 1. SMS Finance (BROKEN)

```
Source: AlRajhi SMS in macOS Messages → chat.db
Step 1 (chat.db): 15+ messages in last 3 days, ALL have m.text=NULL, m.attributedBody has content
Step 2 (import script): Filters `WHERE m.text IS NOT NULL AND length(m.text) > 20` → SKIPS ALL MESSAGES
Step 3 (raw.bank_sms): 1 record total (from Jan 24 test)
Step 4 (finance.transactions): 0 SMS-sourced transactions since Jan 24
Step 5 (Dashboard API): spend_total=0 for today (correct given no data)
```

**Fix**: Extract text from `attributedBody` blob when `m.text` is NULL. The blob is an NSArchiver-encoded NSAttributedString. Python extraction works (verified — see body extraction test above).

### 2. Weight/HealthKit (WORKS)

```
Source: Eufy scale → Apple Health → iOS HealthKit sync → n8n webhook → DB
Step 1 (raw.healthkit_samples): 3 BodyMass entries (Jan 23=108.35, Jan 28=109.3, Jan 29=110.3)
Step 2 (health.metrics): 9 weight records (Jan 20-30), latest=110.30 via ios-app
Step 3 (life.daily_facts): weight_kg=110.30 for Jan 30
Step 4 (Dashboard API): weight_kg=110.3 ✓
Step 5 (App): Should render correctly if it reads API
```

**User report**: "None show in app" — need to verify iOS rendering path. The backend data exists.

### 3. WHOOP (PARTIALLY WORKING)

```
Source: WHOOP API → n8n Direct Sync (every 15 min) → health.whoop_* → normalized → daily_facts
Step 1 (WHOOP API): Returns latest cycle/recovery/sleep
Step 2 (n8n workflow eCu831BkYVoh8Hwv): Active, sequential connections, date fix applied
Step 3 (whoop_recovery): Jan 29 score=85, created Jan 30 07:00 ✓
Step 4 (whoop_sleep): Latest = Jan 29, created Jan 29 00:00 (OLD HA pipeline)
Step 5 (whoop_strain): Latest = Jan 29, created Jan 29 00:00 (OLD HA pipeline)
Step 6 (daily_facts Jan 30): recovery=NULL (cycle not yet closed for today)
Step 7 (feed_status): whoop_recovery=healthy, whoop_sleep=critical, whoop_strain=critical
```

**Issue**: Direct Sync writes recovery but sleep/strain stale because:
- WHOOP API returns latest cycle which may still be open (no sleep/strain until cycle closes)
- Old HA pipeline was writing sleep/strain via different mechanism (HA sensor polling)
- Need to verify Direct Sync actually writes sleep/strain when data is available

### 4. Email Receipts (NEEDS VERIFICATION)

```
Source: Gmail (Carrefour/Careem labels) → n8n cron (every 6h) → parse → finance.receipts
Step 1 (Receipts table): Last = Jan 27 (Carrefour, linked to tx 3341)
Step 2 (n8n workflow 97urYFayj0fr3iNJtpxUW): Active (Carrefour Gmail)
Step 3: Need to verify if new emails exist and workflow executed
```

### 5. Tabby/BNPL (NOT MODELED)

```
Evidence from SMS: "Amount:AED 1244.14 At:Tabby, 800 82229 Date:29/1/26 19:30"
This is the full BNPL plan amount charged to card. Should be modeled as:
- Plan: AED 1244.14 total, 4 installments, ~AED 311 each
- First installment: AED 1244.14/4 charged Jan 29
- Remaining 3 installments: future dates
```

**Fix**: Create BNPL schema + modify SMS classifier to detect Tabby charges.

### 6. Dashboard API (WORKS)

```
dashboard.get_payload() returns:
- weight_kg: 110.3
- recovery_score: null (expected — cycle not closed)
- spend_total: 0 (expected — no SMS ingestion)
- stale_feeds: ['whoop_sleep', 'whoop_strain', 'transactions']
- feed_status: 5 sources with correct timestamps
```

## Fix Priority

| # | Fix | Priority | Impact |
|---|-----|----------|--------|
| 1 | SMS body extraction from attributedBody | P0 | Unblocks ALL finance SMS ingestion |
| 2 | Backfill last 30 days of SMS | P0 | Recovers missing transactions |
| 3 | BNPL data model (Tabby) | P1 | Correct spend modeling |
| 4 | Verify WHOOP Direct Sync writes sleep/strain | P1 | Verify full pipeline |
| 5 | Verify email receipt cron execution | P1 | Ensure receipts flowing |
| 6 | iOS "Data Trust" screen | P1 | User visibility into pipeline health |
| 7 | Replay/idempotency verification | P1 | Safety net |
