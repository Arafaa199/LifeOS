# SMS Transactions Contract

## Overview

Bank SMS messages are the **primary source of truth** for financial transactions.

## Data Flow

```
Bank SMS → macOS Messages → chat.db → fswatch → import-sms-transactions.js → PostgreSQL
```

## Trigger

| Type | Mechanism | Location | Latency |
|------|-----------|----------|---------|
| Primary | fswatch on `~/Library/Messages/chat.db` | Mac (pro14) | Seconds |
| Fallback | launchd timer (15 min) | Mac (pro14) | ≤15 min |

## Supported Banks

| Bank | Sender ID | Currency | Account ID |
|------|-----------|----------|------------|
| AlRajhi Bank | `AlRajhiBank` | SAR | 1 |
| Emirates NBD | `EmiratesNBD` | AED | 2 |
| Jordan Kuwait Bank | `JKB`, `jkb` | JOD | 3 |

## Transaction Types

### Expenses (amount < 0)
- Purchase (PoS, Online)
- ATM Withdrawal
- Bank Fees

### Income (amount > 0)
- Salary (`تم ايداع الراتب`)
- Deposit
- Refund
- Transfer In

## Idempotency

**Key:** `sms-{md5(sender|date|text)[:16]}`

```sql
INSERT INTO finance.transactions (..., external_id, ...)
ON CONFLICT (external_id) DO NOTHING
```

## Schema

```sql
finance.transactions (
    id SERIAL PRIMARY KEY,
    external_id VARCHAR(50) UNIQUE,  -- idempotency key
    account_id INTEGER REFERENCES finance.accounts(id),
    date DATE NOT NULL,
    merchant_name VARCHAR(100),
    merchant_name_clean VARCHAR(100),
    amount NUMERIC(12,2) NOT NULL,   -- negative = expense
    currency VARCHAR(3) DEFAULT 'AED',
    category VARCHAR(50),
    subcategory VARCHAR(50),
    is_grocery BOOLEAN DEFAULT FALSE,
    is_restaurant BOOLEAN DEFAULT FALSE,
    is_food_related BOOLEAN DEFAULT FALSE,
    match_rule_id INTEGER REFERENCES finance.merchant_rules(id),
    raw_data JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
)
```

## Auto-Categorization

On INSERT, trigger `finance.categorize_transaction()` applies merchant rules:

1. Match `merchant_name` against `finance.merchant_rules.merchant_pattern`
2. Apply highest priority match
3. Set `category`, `subcategory`, `is_grocery`, `is_restaurant`, `is_food_related`
4. Record `match_rule_id` for audit

## Invariants

1. **No duplicates** - `external_id` UNIQUE constraint
2. **No manual deletes** - Only quarantine suspect data
3. **Amounts signed** - Expenses negative, income positive
4. **Timezone** - Business dates use Asia/Dubai (UTC+4)

## Files

| File | Purpose |
|------|---------|
| `scripts/import-sms-transactions.js` | Parser + importer |
| `~/Library/LaunchAgents/com.nexus.sms-watcher.plist` | fswatch trigger |
| `~/Library/LaunchAgents/com.nexus.sms-import.plist` | 15-min fallback |

---

*Last updated: 2026-01-22*
