# Ledger Contract

## Overview

The ledger is the **unified view** of all financial data. SMS transactions are the spine; receipts and categorization enrich them.

## Data Sources (Priority Order)

| Source | Role | Idempotency Key |
|--------|------|-----------------|
| SMS Transactions | Primary spine | `sms-{md5(sender\|date\|text)[:16]}` |
| Email Receipts | Line item enrichment | `pdf_hash` (SHA256) |
| Manual Entries | Gap filling | `client_id` (UUID from iOS) |

## Entity Relationships

```
finance.accounts (1) ─────< (N) finance.transactions
                                      │
                                      ├──< finance.receipts (linked)
                                      │         │
                                      │         └──< finance.receipt_items
                                      │
                                      └──> finance.merchant_rules (categorization)
                                                │
                                                └──> finance.categories
```

## Transaction Lifecycle

```
1. SMS arrives → import-sms-transactions.js
2. INSERT with external_id → ON CONFLICT DO NOTHING (idempotent)
3. Trigger fires → categorize_transaction() applies merchant rules
4. Hourly: receipt-ingest links matching receipts
5. Manual: iOS app can override category
```

## Categorization Hierarchy

| Level | Source | Priority |
|-------|--------|----------|
| Auto | `finance.merchant_rules` trigger | Default |
| Manual | iOS app override | Highest |
| Fallback | "Uncategorized" | Lowest |

## Classification Flags

| Flag | Meaning | Use Case |
|------|---------|----------|
| `is_grocery` | Supermarket purchase | Grocery budget tracking |
| `is_restaurant` | Dining/delivery | Eating out budget |
| `is_food_related` | Any food spend | Total food budget |

## Accounts

| ID | Name | Institution | Currency |
|----|------|-------------|----------|
| 1 | AlRajhi | AlRajhi Bank | SAR |
| 2 | Emirates NBD | Emirates NBD | AED |
| 3 | JKB | Jordan Kuwait Bank | JOD |

## Business Date Rules

**Timezone:** Asia/Dubai (UTC+4)

```sql
-- Convert timestamp to business date
SELECT finance.to_business_date(transaction_at) AS business_date;

-- Midnight boundary: 20:00 UTC = 00:00 Dubai (next day)
```

## Aggregation Views

| View | Purpose |
|------|---------|
| `finance.budget_status` | Budget vs actual by category |
| `finance.upcoming_recurring` | Predicted recurring expenses |
| `life.daily_facts` | Daily spending aggregates |

## Data Quality

### Quarantine (not delete)
```sql
UPDATE finance.transactions SET is_quarantined = true, quarantine_reason = 'reason'
WHERE <suspect condition>;
```

### Suspect Conditions
- Date before 2020 (likely parse error)
- Date in future (>7 days ahead)
- Amount > 100,000 (likely missing decimal)

## Invariants

1. **SMS is truth** - Never delete SMS-sourced transactions
2. **Receipts link, don't replace** - `linked_transaction_id` is FK, not merge
3. **Idempotent ingestion** - Re-runs are safe via ON CONFLICT
4. **Audit trail** - `match_rule_id`, `match_reason` explain categorization
5. **Timezone consistency** - All business dates use Asia/Dubai

## Related Contracts

- `sms-transactions.md` - SMS ingestion details
- `receipts.md` - Receipt ingestion details
- `vendors.md` - Adding new receipt vendors

---

*Last updated: 2026-01-22*
