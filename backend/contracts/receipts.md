# Receipts Contracts

Receipt parsing and nutrition linking.

## GET /webhook/nexus-receipts

Fetches receipt summaries.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |

### Response

```json
{
  "success": true,
  "receipts": [
    {
      "id": 1,
      "vendor": "Carrefour",
      "store_name": "Carrefour Hypermarket",
      "receipt_date": "2026-02-08",
      "total_amount": 250.50,
      "currency": "AED",
      "parse_status": "success",
      "linked_transaction_id": 123,
      "item_count": 15,
      "matched_count": 12
    }
  ],
  "count": 18
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `ReceiptModels.swift` → `ReceiptsResponse`, `ReceiptSummary` |
| n8n Workflow | `receipts-webhooks.json` |
| DB Tables | `finance.receipts`, `finance.receipt_items` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## GET /webhook/nexus-receipt-detail

Fetches a single receipt with line items.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |
| Query Params | `id` (receipt ID) |

### Response

```json
{
  "success": true,
  "receipt": {
    "id": 1,
    "vendor": "Carrefour",
    "store_name": "Carrefour Hypermarket",
    "store_address": "Dubai Mall, Dubai",
    "receipt_date": "2026-02-08",
    "receipt_time": "14:30",
    "invoice_number": "INV-12345",
    "subtotal": 238.57,
    "vat_amount": 11.93,
    "total_amount": 250.50,
    "currency": "AED",
    "linked_transaction_id": 123,
    "link_method": "amount_date",
    "items": [
      {
        "id": 1,
        "line_number": 1,
        "item_description": "Organic Chicken Breast 1kg",
        "item_description_clean": "Chicken Breast",
        "quantity": 1,
        "unit": "kg",
        "unit_price": 45.00,
        "line_total": 45.00,
        "is_promotional": false,
        "discount_amount": null,
        "matched_food_id": 12345,
        "match_confidence": 0.95,
        "is_user_confirmed": true,
        "food_name": "Chicken Breast",
        "food_brand": "Generic",
        "calories_per_100g": 165,
        "protein_per_100g": 31,
        "carbs_per_100g": 0,
        "fat_per_100g": 3.6,
        "serving_size_g": 100
      }
    ]
  }
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `ReceiptModels.swift` → `ReceiptDetailResponse`, `ReceiptDetail`, `ReceiptItem` |
| n8n Workflow | `receipts-webhooks.json` |
| DB Tables | `finance.receipts`, `finance.receipt_items` |

### Error Responses

`UNAUTHORIZED`, `NOT_FOUND`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-receipt-item-match

Links a receipt item to a food.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "item_id": 123,
  "food_id": 456,
  "is_user_confirmed": true
}
```

### Response

```json
{
  "success": true,
  "item": {
    "id": 123,
    "matched_food_id": 456,
    "match_confidence": 1.0,
    "is_user_confirmed": true
  }
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `ReceiptModels.swift` → `ReceiptItemMatchRequest`, `ReceiptItemMatchResponse` |
| n8n Workflow | `receipts-webhooks.json` |
| DB Table | `finance.receipt_items` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `NOT_FOUND`, `INTERNAL_ERROR`

---

## GET /webhook/nexus-receipt-nutrition

Gets nutrition summary for a receipt.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |
| Query Params | `id` (receipt ID) |

### Response

```json
{
  "success": true,
  "nutrition": {
    "total_items": 15,
    "matched_items": 12,
    "total_calories": 4500,
    "total_protein": 180,
    "total_carbs": 350,
    "total_fat": 150
  }
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `ReceiptModels.swift` → `ReceiptNutritionResponse`, `ReceiptNutritionSummary` |
| n8n Workflow | `receipts-webhooks.json` |
| DB Tables | `finance.receipt_items`, `nutrition.foods` |

### Error Responses

`UNAUTHORIZED`, `NOT_FOUND`, `INTERNAL_ERROR`

---

## Receipt Sources

| Vendor | Source | Parser |
|--------|--------|--------|
| Carrefour | Gmail PDF | `backend/scripts/receipt-ingest/carrefour.py` |
| Careem | Gmail HTML | `backend/scripts/receipt-ingest/careem.py` |

## Auto-Matching

Migration 167 added auto-matching for receipt items:

```sql
-- Trigger on INSERT
CREATE TRIGGER tr_auto_match_receipt_item
AFTER INSERT ON finance.receipt_items
FOR EACH ROW EXECUTE FUNCTION finance.auto_match_receipt_item();
```

Auto-matching uses:
1. Barcode lookup (if available)
2. Trigram similarity search on item description
3. 0.3 confidence threshold for auto-match

## iOS Implementation Status

- `ReceiptsListView.swift` - List all receipts
- `ReceiptDetailView.swift` - View receipt with items
- `FoodMatchSheet.swift` - Manual food matching

All implemented via `ReceiptsViewModel.swift`.
