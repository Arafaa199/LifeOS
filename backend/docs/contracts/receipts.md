# Receipts Contract

## Overview

Email receipts provide **itemized details** for transactions. They link to SMS transactions, not replace them.

## Data Flow

```
Gmail → Gmail API → receipt_ingestion.py → PDF storage + PostgreSQL
                         ↓
              carrefour_parser.py → Line items
```

## Trigger

| Type | Mechanism | Location | Frequency |
|------|-----------|----------|-----------|
| Primary | systemd timer | nexus server | Hourly |
| Manual | `docker compose run` | nexus server | On-demand |

## Supported Vendors

| Vendor | Gmail Label | Parser | Status |
|--------|-------------|--------|--------|
| Carrefour UAE | `LifeOS/Receipts/Carrefour` | `carrefour_parser.py` | PROD |

## Document Types

| doc_type | parse_status | Action |
|----------|--------------|--------|
| `tax_invoice` | `success` | Parse line items |
| `tips_receipt` | `skipped` | Store PDF only |
| `refund_note` | `skipped` | Store PDF only |

## Idempotency

**Key:** `pdf_hash` (SHA256 of PDF content)

```sql
INSERT INTO finance.receipts (..., pdf_hash, ...)
-- Duplicate PDFs detected by hash before INSERT
```

## Schema

```sql
finance.receipts (
    id SERIAL PRIMARY KEY,
    gmail_message_id VARCHAR(100),
    pdf_hash VARCHAR(64) UNIQUE,      -- SHA256
    pdf_path VARCHAR(255),
    vendor VARCHAR(50),
    store_location VARCHAR(100),
    receipt_date DATE,
    receipt_time TIME,
    subtotal NUMERIC(10,2),
    tax_amount NUMERIC(10,2),
    total_amount NUMERIC(10,2),
    currency VARCHAR(3) DEFAULT 'AED',
    doc_type VARCHAR(50),             -- tax_invoice, tips_receipt, refund_note
    parse_status VARCHAR(20),         -- pending, success, failed, skipped
    parse_error TEXT,
    linked_transaction_id INTEGER REFERENCES finance.transactions(id),
    raw_text TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
)

finance.receipt_items (
    id SERIAL PRIMARY KEY,
    receipt_id INTEGER REFERENCES finance.receipts(id),
    item_name VARCHAR(255),
    quantity NUMERIC(10,3),
    unit_price NUMERIC(10,2),
    total_price NUMERIC(10,2),
    category VARCHAR(50),
    barcode VARCHAR(50)
)
```

## Transaction Linking

Receipts link to SMS transactions by matching:
1. Date (±1 day tolerance)
2. Amount (exact match on total)
3. Vendor pattern (CARREFOUR in merchant_name)

```sql
UPDATE finance.receipts SET linked_transaction_id = t.id
FROM finance.transactions t
WHERE receipts.receipt_date BETWEEN t.date - 1 AND t.date + 1
  AND receipts.total_amount = ABS(t.amount)
  AND t.merchant_name ILIKE '%CARREFOUR%'
```

## Invariants

1. **SMS is primary** - Receipts supplement, don't replace transactions
2. **No duplicate PDFs** - `pdf_hash` prevents re-ingestion
3. **Preserve originals** - PDFs stored permanently in `~/lifeos/data/receipts/`
4. **Skip non-invoices** - Tips and refunds stored but not parsed

## Files

| Location | Purpose |
|----------|---------|
| `~/lifeos/receipt-ingest/` | Application code (server) |
| `~/lifeos/secrets/` | Gmail OAuth credentials |
| `~/lifeos/data/receipts/` | PDF storage (hash-based paths) |
| `~/.config/systemd/user/receipt-ingest.timer` | Hourly trigger |

## Adding New Vendors

See `docs/contracts/vendors.md` for the vendor scaffold pattern.

---

*Last updated: 2026-01-22*
