# Data Architecture Contracts

System-level contracts for data flow, ledger design, and ingestion pipelines.

---

## Ledger Contract

The ledger is the **unified view** of all financial data. SMS transactions are the spine; receipts and categorization enrich them.

### Data Sources (Priority Order)

| Source | Role | Idempotency Key |
|--------|------|-----------------|
| SMS Transactions | Primary spine | `sms-{md5(sender|date|text)[:16]}` |
| Email Receipts | Line item enrichment | `pdf_hash` (SHA256) |
| Manual Entries | Gap filling | `client_id` (UUID from iOS) |

### Entity Relationships

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

### Transaction Lifecycle

```
1. SMS arrives → import-sms-transactions.js
2. INSERT with external_id → ON CONFLICT DO NOTHING (idempotent)
3. Trigger fires → categorize_transaction() applies merchant rules
4. Hourly: receipt-ingest links matching receipts
5. Manual: iOS app can override category
```

### Categorization Hierarchy

| Level | Source | Priority |
|-------|--------|----------|
| Auto | `finance.merchant_rules` trigger | Default |
| Manual | iOS app override | Highest |
| Fallback | "Uncategorized" | Lowest |

### Classification Flags

| Flag | Meaning | Use Case |
|------|---------|----------|
| `is_grocery` | Supermarket purchase | Grocery budget tracking |
| `is_restaurant` | Dining/delivery | Eating out budget |
| `is_food_related` | Any food spend | Total food budget |

---

## SMS Transactions Contract

### Source

- iOS Messages database: `~/Library/Messages/chat.db`
- Watched by: `com.nexus.sms-watcher` (fswatch)
- Fallback: `com.nexus.sms-import` (15-min cron)

### Parser

Script: `backend/scripts/import-sms-transactions.js`

### Supported Banks

| Bank | Sender Pattern | Currency |
|------|----------------|----------|
| Al Rajhi | `AlRajhiBank` | SAR |
| Emirates NBD | `EmiratesNBD` | AED |
| JKB | `JKB` | JOD |

### Message Format

```
Al Rajhi: Purchase from {merchant} for {amount} SAR on {date}
Emirates NBD: AED {amount} purchase at {merchant} on {date}
```

### Parsing Output

```json
{
  "amount": -150.00,
  "currency": "AED",
  "merchant_name": "CARREFOUR",
  "date": "2026-02-08",
  "external_id": "sms-a1b2c3d4e5f6",
  "source": "sms"
}
```

### Idempotency

`external_id = 'sms-' + md5(sender|date|text)[:16]`

---

## Receipt Ingestion Contract

### Sources

| Vendor | Email Label | Frequency |
|--------|-------------|-----------|
| Carrefour | `receipts/carrefour` | 6h cron |
| Careem | `receipts/careem` | 6h cron |

### Pipeline

```
1. Gmail API → fetch emails with label
2. Extract PDF/HTML attachment
3. Parse with vendor-specific parser
4. SHA256 hash for dedup
5. UPSERT to finance.receipts
6. INSERT line items to finance.receipt_items
7. Match to transaction by amount+date
```

### Parsers

| Vendor | Script | Output |
|--------|--------|--------|
| Carrefour | `carrefour.py` | PDF → structured JSON |
| Careem | `careem.py` | HTML → structured JSON |

### Linking Logic

```sql
-- Find matching transaction
SELECT id FROM finance.transactions
WHERE date = receipt_date
  AND ABS(amount - total_amount) < 1.00
  AND NOT EXISTS (SELECT 1 FROM finance.receipts WHERE linked_transaction_id = id)
ORDER BY ABS(amount - total_amount)
LIMIT 1;
```

---

## Vendors Contract

Adding a new receipt vendor:

### 1. Create Parser

```python
# backend/scripts/receipt-ingest/{vendor}.py

def parse_receipt(content: bytes) -> dict:
    return {
        "vendor": "vendor_name",
        "store_name": "...",
        "receipt_date": "YYYY-MM-DD",
        "total_amount": 123.45,
        "currency": "AED",
        "items": [
            {
                "item_description": "...",
                "quantity": 1,
                "unit_price": 10.00,
                "line_total": 10.00
            }
        ]
    }
```

### 2. Register in Gmail Automation

Add to `carrefour-gmail-automation.json` or create new workflow.

### 3. Add Merchant Rules

```sql
INSERT INTO finance.merchant_rules (merchant_pattern, category, is_grocery, confidence)
VALUES ('VENDOR_NAME', 'Grocery', true, 90);
```

---

## Business Date Rules

**Timezone:** Asia/Dubai (UTC+4)

```sql
-- Convert timestamp to business date
SELECT finance.to_business_date(transaction_at) AS business_date;

-- Today in Dubai
SELECT life.dubai_today();
```

### Midnight Boundary

- 20:00 UTC = 00:00 Dubai (next day)
- All aggregations use Dubai business date

---

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

---

## Invariants

1. **SMS is truth** - Never delete SMS-sourced transactions
2. **Receipts link, don't replace** - `linked_transaction_id` is FK, not merge
3. **Idempotent ingestion** - Re-runs are safe via ON CONFLICT
4. **Audit trail** - `match_rule_id`, `match_reason` explain categorization
5. **Timezone consistency** - All business dates use Asia/Dubai

---

## Key Database Functions

| Function | Purpose |
|----------|---------|
| `life.dubai_today()` | Current date in Dubai timezone |
| `finance.to_business_date(ts)` | Convert timestamp to Dubai date |
| `finance.categorize_transaction(id)` | Apply merchant rules |
| `finance.refresh_financial_truth()` | Rebuild materialized views |
| `nutrition.search_foods(query)` | Trigram search on foods |
| `nutrition.lookup_barcode(code)` | Barcode → food lookup |
| `dashboard.get_payload()` | Full dashboard JSON |
| `life.explain_today(date)` | Generate day briefing |

---

## Aggregation Views

| View | Purpose |
|------|---------|
| `finance.budget_status` | Budget vs actual by category |
| `finance.upcoming_recurring` | Predicted recurring expenses |
| `finance.mv_monthly_spend` | Monthly spending materialized |
| `life.daily_facts` | Daily aggregates across domains |
| `life.v_active_reminders` | Non-completed reminders |

---

*Merged from: backend/docs/contracts/ledger.md, sms-transactions.md, receipts.md, vendors.md*
