# Income Ingestion Audit - Design Note

## Audit Questions & Answers

### Q1: Is ingestion triggered automatically on message arrival?

**YES** - SMS-based income (including salary) is already event-driven.

| Component | Trigger | Latency |
|-----------|---------|---------|
| `com.nexus.sms-watcher` | `fswatch` on `~/Library/Messages/chat.db` | Seconds |
| `com.nexus.sms-import` | 15-min launchd fallback | ≤15 min |

**Evidence:**
```
$ launchctl list | grep sms
88165  0  com.nexus.sms-watcher  # Running continuously
```

### Q2: What is the trigger source?

**SMS only.**

| Bank | Sender ID | Income Types |
|------|-----------|--------------|
| Emirates NBD | EmiratesNBD | Salary (Arabic: تم ايداع الراتب) |
| AlRajhi | AlRajhiBank | Salary, Credit, Refund |
| JKB | JKB/jkb | Deposit |

**No email ingestion for bank statements exists.**

### Q3: What idempotency key is used?

**MD5 hash of `sender|date|text`**

```javascript
// import-sms-transactions.js:360-362
function generateExternalId(sender, date, text) {
  const hash = createHash('md5').update(`${sender}|${date}|${text}`).digest('hex');
  return `sms-${hash.substring(0, 16)}`;
}
```

**Database enforcement:**
```sql
INSERT INTO finance.transactions (..., external_id, ...)
VALUES (...)
ON CONFLICT (external_id) DO NOTHING
```

**Verified working:**
```sql
SELECT external_id, merchant_name, amount FROM finance.transactions
WHERE merchant_name = 'Salary';
-- sms-15621e11471716ab | Salary | 23500.00
-- sms-cb10900af173553a | Salary | 23500.00
```

---

## Gap Analysis

| Source | Event-Driven | Idempotent | Notes |
|--------|--------------|------------|-------|
| SMS (salary) | ✅ Yes | ✅ Yes | Already working |
| SMS (expenses) | ✅ Yes | ✅ Yes | Already working |
| Email (statements) | ❌ No | N/A | Not implemented |
| Email (receipts) | ✅ Yes | ✅ Yes | Hourly on server |

**Conclusion:** SMS income ingestion is already fully event-driven. No fix needed.

---

## Decision

### No Change Required for Income Ingestion

The current SMS-based salary ingestion is:
1. **Event-driven** via fswatch (seconds latency)
2. **Idempotent** via MD5 hash external_id
3. **Working** (2 salary deposits captured: 2026-01-03, 2025-12-05)

### Future Enhancement (Not Now)

If email-based bank statement ingestion is desired later:
1. Create Gmail label `LifeOS/Statements/Emirates-NBD`
2. Reuse receipt ingestion pattern (hourly poll on server)
3. Parse PDF/CSV statements for transaction data
4. Use `email-{hash}` as external_id

**Priority:** Low. SMS captures real-time transactions; statements are redundant.

---

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────┐
│                    INCOME SOURCES                           │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  SMS (Mac)                     Email (Server)               │
│  ├─ fswatch chat.db            ├─ Gmail API hourly          │
│  ├─ import-sms-transactions.js │  └─ Receipts only (now)    │
│  ├─ Salary ✓                   │                            │
│  ├─ Refunds ✓                  │                            │
│  └─ external_id: sms-{hash}    │                            │
│                                                              │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │   PostgreSQL     │
                    │   nexus.finance  │
                    └──────────────────┘
```

---

*Created: 2026-01-22*
