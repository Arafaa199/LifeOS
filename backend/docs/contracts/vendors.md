# Vendors Contract

## Overview

Vendors are email receipt sources. Each vendor has a Gmail label, parser, and document type handling.

## Vendor Registry

| Vendor | Gmail Label | Parser Module | Status |
|--------|-------------|---------------|--------|
| Carrefour UAE | `LifeOS/Receipts/Carrefour` | `carrefour_parser.py` | PROD |
| _template_ | `LifeOS/Receipts/{Vendor}` | `{vendor}_parser.py` | - |

## Adding a New Vendor

### 1. Gmail Setup (Manual)

```
1. Create label: LifeOS/Receipts/{VendorName}
2. Create filter:
   - From: {sender@vendor.com}
   - Subject contains: {receipt keywords}
   - Apply label: LifeOS/Receipts/{VendorName}
```

### 2. Parser Module

Create `{vendor}_parser.py` with required interface:

```python
def detect_document_type(pdf_text: str) -> str:
    """
    Returns: 'tax_invoice', 'tips_receipt', 'refund_note', or 'unknown'
    """
    pass

def parse_receipt(pdf_text: str) -> dict:
    """
    Returns: {
        'vendor': str,
        'store_location': str,
        'receipt_date': date,
        'receipt_time': time,
        'subtotal': Decimal,
        'tax_amount': Decimal,
        'total_amount': Decimal,
        'currency': str,
        'items': [
            {
                'item_name': str,
                'quantity': Decimal,
                'unit_price': Decimal,
                'total_price': Decimal,
                'category': str,  # optional
                'barcode': str,   # optional
            }
        ]
    }
    """
    pass
```

### 3. Configuration

Add to `receipt_ingestion.py` vendor config:

```python
VENDORS = {
    'carrefour': {
        'gmail_label': 'LifeOS/Receipts/Carrefour',
        'parser': carrefour_parser,
        'merchant_pattern': '%CARREFOUR%',
    },
    # Add new vendor here
}
```

### 4. Database Entry

```sql
-- Add vendor to tracking table (if exists)
INSERT INTO finance.vendors (name, gmail_label, parser_module, status)
VALUES ('VendorName', 'LifeOS/Receipts/VendorName', 'vendor_parser.py', 'active');
```

### 5. Merchant Rules

```sql
-- Add transaction matching rule
INSERT INTO finance.merchant_rules
    (merchant_pattern, category, subcategory, is_grocery, is_food_related, priority)
VALUES
    ('%VENDORNAME%', 'Grocery', 'Supermarket', true, true, 10);
```

## Vendor Config Table (Optional)

```sql
CREATE TABLE finance.vendors (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL,
    gmail_label VARCHAR(100) NOT NULL,
    parser_module VARCHAR(100) NOT NULL,
    merchant_pattern VARCHAR(100),
    status VARCHAR(20) DEFAULT 'active',  -- active, disabled, testing
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

## Document Type Handling

| doc_type | Action | Stored | Parsed | Linked |
|----------|--------|--------|--------|--------|
| tax_invoice | Full parse | Yes | Yes | Yes |
| tips_receipt | Skip parse | Yes | No | No |
| refund_note | Skip parse | Yes | No | No |
| unknown | Fail | Yes | No | No |

## Testing New Vendor

```bash
# 1. Test parser locally
python -c "from vendor_parser import parse_receipt; print(parse_receipt(open('test.pdf').read()))"

# 2. Dry run ingestion
docker compose run --rm receipt-ingest --fetch --dry-run

# 3. Full test
docker compose run --rm receipt-ingest --all
```

## Planned Vendors

| Vendor | Priority | Notes |
|--------|----------|-------|
| Lulu Hypermarket | Medium | Similar format to Carrefour |
| Amazon.ae | Medium | Different email format |
| Noon | Low | Delivery receipts |

---

*Last updated: 2026-01-22*
