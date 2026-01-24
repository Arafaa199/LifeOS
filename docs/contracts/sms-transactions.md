# SMS Transactions Contract

## Overview

Bank SMS messages are the **primary source of truth** for financial transactions.

## Architecture (v2)

```
Bank SMS → macOS Messages → chat.db → fswatch → import-sms-transactions.js
                                                        ↓
                                              sms-classifier.js
                                              (YAML patterns)
                                                        ↓
                                              PostgreSQL → finance.transactions
```

## Classifier

The SMS classifier (`sms-classifier.js`) uses patterns from `sms_regex_patterns.yaml`:

- **28 transaction patterns** across 5 banks/services
- **8 exclude patterns** (OTP, promo, security notifications)
- **Deterministic regex matching** (no LLM)
- **Intent-based routing**: income, expense, transfer, refund, declined

## Trigger

| Type | Mechanism | Location | Latency |
|------|-----------|----------|---------|
| Primary | fswatch on `~/Library/Messages/chat.db` | Mac (pro14) | Seconds |
| Fallback | launchd timer (15 min) | Mac (pro14) | ≤15 min |

## Supported Banks

| Bank | Sender ID | Account ID | Currencies |
|------|-----------|------------|------------|
| AlRajhi Bank | `AlRajhiBank` | 1 | SAR, USD, EUR, GBP |
| Emirates NBD | `EmiratesNBD` | 2 | AED, SAR, JOD, USD, EUR, GBP |
| Jordan Kuwait Bank | `JKB`, `jkb` | 3 | JOD, SAR, AED, BHD, EGP, USD, EUR, GBP |
| CAREEM | `CAREEM` | - | AED, SAR, JOD (refunds only) |
| Amazon | `Amazon` | - | SAR, AED (refund notifications) |

## Intent Routing

| Intent | Action | Amount Sign |
|--------|--------|-------------|
| `income` | Create transaction | Positive |
| `expense` | Create transaction | Negative |
| `transfer` | Create transaction | Negative |
| `refund` | Create transaction | Positive |
| `declined` | Skip (no transaction) | N/A |
| `excluded` | Skip (OTP/promo) | N/A |

## Idempotency

**Key:** `sms:<message_rowid>`

```sql
INSERT INTO finance.transactions (..., external_id, ...)
ON CONFLICT (external_id) DO NOTHING
```

Using message ROWID (stable SQLite identifier) instead of content hash for more reliable deduplication.

## Schema

```sql
finance.transactions (
    id SERIAL PRIMARY KEY,
    external_id VARCHAR(100) UNIQUE,  -- sms:<rowid>
    account_id INTEGER REFERENCES finance.accounts(id),
    date DATE NOT NULL,
    merchant_name VARCHAR(200),
    merchant_name_clean VARCHAR(200),
    amount NUMERIC(10,2) NOT NULL,    -- negative = expense
    currency VARCHAR(3) DEFAULT 'AED',
    category VARCHAR(50),
    match_rule_id INTEGER REFERENCES finance.merchant_rules(id),
    raw_data JSONB,                   -- Contains: sender, pattern, intent, entities
    created_at TIMESTAMP DEFAULT NOW()
)
```

## raw_data Structure

```json
{
  "sender": "EmiratesNBD",
  "pattern": "debit_purchase",
  "intent": "expense",
  "entities": {
    "currency": "AED",
    "amount": "165.00",
    "merchant": "BARBERSHOP",
    "city": "Dubai"
  },
  "confidence": 0.95,
  "original_text": "..."
}
```

## Auto-Categorization

On INSERT, trigger `finance.categorize_transaction()` applies merchant rules:

1. Match `merchant_name` against `finance.merchant_rules.merchant_pattern`
2. Apply highest priority match
3. Set `category`, `subcategory`, `is_grocery`, `is_restaurant`, `is_food_related`
4. Record `match_rule_id` for audit

## Files

| File | Purpose |
|------|---------|
| `scripts/sms-classifier.js` | YAML-based pattern classifier |
| `scripts/import-sms-transactions.js` | Main importer (uses classifier) |
| `scripts/backfill-sms.js` | Backfill from chat.db copy |
| `LifeOS-Ops/artifacts/sms_regex_patterns.yaml` | Pattern definitions |
| `LifeOS-Ops/artifacts/test_sms_patterns.py` | Pattern validation |

## Pattern File Location

Patterns are defined in `~/Cyber/Dev/LifeOS-Ops/artifacts/sms_regex_patterns.yaml`:

```yaml
emiratesnbd:
  sender: "EmiratesNBD"
  patterns:
    - name: debit_purchase
      intent: expense
      regex: 'تمت عملية شراء بقيمة\s+(?P<currency>...)...'
      entities: [currency, amount, merchant, city]
```

## Backfill

To backfill from a copy of chat.db:

```bash
# Copy Messages database (requires Full Disk Access)
cp ~/Library/Messages/chat.db ~/tmp/lifeos_sms/chat.db

# Run backfill
cd ~/Cyber/Infrastructure/Nexus-setup/scripts
export $(cat ../.env | xargs)
node backfill-sms.js ~/tmp/lifeos_sms/chat.db 730  # Last 2 years
```

## Invariants

1. **No duplicates** - `external_id` UNIQUE constraint with `sms:<rowid>` format
2. **No manual deletes** - Only quarantine suspect data
3. **Amounts signed** - Expenses negative, income positive
4. **Timezone** - Business dates use Asia/Dubai (UTC+4)
5. **Deterministic** - Same input always produces same classification

---

*Last updated: 2026-01-24*
