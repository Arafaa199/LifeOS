# Finance Contracts

## GET /webhook/nexus-finance-summary

Fetches finance summary including today's spend, MTD totals, transactions, budgets.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |

### Response

```json
{
  "success": true,
  "data": {
    "total_spent": 150.00,
    "grocery_spent": 45.00,
    "eating_out_spent": 35.00,
    "currency": "AED",
    "total_income": 15000.00,
    "mtd_spend": 3500.00,
    "recent_transactions": [
      {
        "id": 123,
        "date": "2026-02-08",
        "merchant_name": "Carrefour",
        "amount": -45.00,
        "currency": "AED",
        "category": "Grocery",
        "subcategory": null,
        "is_grocery": true,
        "is_restaurant": false,
        "notes": null,
        "tags": []
      }
    ],
    "budgets": [
      {
        "id": 1,
        "month": "2026-02",
        "category": "Grocery",
        "budget_amount": 2000,
        "spent": 450,
        "remaining": 1550
      }
    ],
    "category_breakdown": {
      "Grocery": 450,
      "Restaurant": 350,
      "Transport": 200
    }
  }
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `FinanceModels.swift` → `FinanceSummary`, `Transaction`, `Budget` |
| n8n Workflow | `finance-summary-webhook.json` |
| DB Tables | `finance.transactions`, `finance.budgets`, `life.daily_facts` |
| Schema | `_schemas/nexus-finance-summary.json` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## GET /webhook/nexus-transactions

Fetches paginated transactions.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |
| Query Params | `offset` (int, default 0), `limit` (int, default 50) |

### Response

```json
{
  "success": true,
  "transactions": [...],
  "count": 150,
  "offset": 0,
  "limit": 50
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `FinanceModels.swift` → `Transaction` |
| n8n Workflow | `finance-summary-webhook.json` |
| DB Table | `finance.transactions` |

### Error Responses

`UNAUTHORIZED`, `VALIDATION_ERROR`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-expense

Logs a quick expense via natural language.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "text": "Coffee 25 AED",
  "client_id": "uuid-v4"
}
```

### Response

```json
{
  "success": true,
  "message": "Expense logged",
  "data": {
    "transaction": {
      "id": 123,
      "merchant_name": "Coffee",
      "amount": -25.00,
      "currency": "AED",
      "category": "Restaurant"
    }
  }
}
```

### Idempotency

`client_id` UUID with `ON CONFLICT DO NOTHING`

### References

| Type | Reference |
|------|-----------|
| iOS Model | `FinanceModels.swift` → `QuickExpenseRequest` |
| n8n Workflow | `expense-log-webhook.json` |
| DB Table | `finance.transactions` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `CONFLICT`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-transaction

Logs a structured transaction.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "merchant_name": "Carrefour",
  "amount": -150.00,
  "category": "Grocery",
  "notes": "Weekly groceries",
  "date": "2026-02-08",
  "client_id": "uuid-v4"
}
```

### Response

```json
{
  "success": true,
  "data": {
    "transaction": { "id": 124, "merchant_name": "Carrefour", ... }
  }
}
```

### Idempotency

`client_id` UUID

### References

| Type | Reference |
|------|-----------|
| iOS Model | `FinanceModels.swift` → `AddTransactionRequest` |
| n8n Workflow | `smart-entry-local-first.json` |
| DB Table | `finance.transactions` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `CONFLICT`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-update-transaction

Updates an existing transaction.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "id": 123,
  "merchant_name": "Updated Merchant",
  "amount": -30.00,
  "category": "Restaurant",
  "notes": "Updated notes",
  "date": "2026-02-08"
}
```

### Response

```json
{
  "success": true,
  "message": "Transaction updated"
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `FinanceModels.swift` → `UpdateTransactionRequest` |
| n8n Workflow | `transaction-update-webhook.json` |
| DB Table | `finance.transactions` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `NOT_FOUND`, `INTERNAL_ERROR`

---

## DELETE /webhook/nexus-delete-transaction

Deletes a transaction.

| Field | Value |
|-------|-------|
| Method | DELETE |
| Auth | X-API-Key header |
| Query Params | `id` (transaction ID) |

### Delete Semantics

**HARD DELETE** — Row is permanently removed from `finance.transactions`. This is irreversible.

### Response

```json
{
  "success": true,
  "message": "Transaction deleted"
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `FinanceAPI.swift` → `deleteTransaction()` |
| n8n Workflow | `transaction-delete-webhook.json` |
| DB Table | `finance.transactions` |

### Error Responses

`UNAUTHORIZED`, `NOT_FOUND`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-income

Logs income.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "source": "Salary",
  "amount": 15000.00,
  "category": "Salary",
  "notes": "January salary",
  "date": "2026-02-01",
  "is_recurring": true,
  "client_id": "uuid-v4"
}
```

### Response

```json
{
  "success": true,
  "data": { "transaction": { "id": 125 } }
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `FinanceModels.swift` → `AddIncomeRequest` |
| n8n Workflow | `income-webhook.json` |
| DB Table | `finance.transactions` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `CONFLICT`, `INTERNAL_ERROR`

---

## GET /webhook/nexus-budgets

Fetches current month's budgets.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |

### Response

```json
{
  "success": true,
  "data": {
    "budgets": [
      {
        "id": 1,
        "month": "2026-02",
        "category": "Grocery",
        "budget_amount": 2000,
        "spent": 450,
        "remaining": 1550
      }
    ]
  }
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `FinanceModels.swift` → `BudgetsResponse`, `Budget` |
| n8n Workflow | `budget-fetch-webhook.json` |
| DB Table | `finance.budgets` |
| Schema | `_schemas/nexus-budgets.json` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-budgets

Creates or updates a budget (UPSERT by month+category).

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "month": "2026-02",
  "category": "Grocery",
  "budget_amount": 2500,
  "category_id": 1,
  "notes": "Increased budget"
}
```

### Response

```json
{
  "success": true,
  "data": { "budget": { "id": 1, ... } }
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `FinanceModels.swift` → `CreateBudgetRequest` |
| n8n Workflow | `budget-set-webhook.json` |
| DB Table | `finance.budgets` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `INTERNAL_ERROR`

---

## GET /webhook/nexus-categories

Fetches expense/income categories.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |

### Response

```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "name": "Grocery",
      "type": "expense",
      "icon": "cart.fill",
      "color": "#4CAF50",
      "is_active": true,
      "display_order": 1
    }
  ]
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `FinanceModels.swift` → `CategoriesResponse`, `Category` |
| n8n Workflow | `finance-planning-api.json` |
| DB Table | `finance.categories` |
| Schema | `_schemas/nexus-categories.json` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## GET /webhook/nexus-recurring

Fetches recurring items (bills, subscriptions).

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |

### Response

```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "name": "Netflix",
      "amount": 65.00,
      "currency": "AED",
      "type": "expense",
      "cadence": "monthly",
      "day_of_month": 15,
      "day_of_week": null,
      "next_due_date": "2026-02-15",
      "last_occurrence": "2026-01-15",
      "category_id": 5,
      "merchant_pattern": "NETFLIX",
      "is_active": true,
      "auto_create": false,
      "notes": null,
      "created_at": "2025-01-01T00:00:00Z",
      "updated_at": "2026-01-15T12:00:00Z",
      "category_name": "Entertainment",
      "category_icon": "tv.fill",
      "days_until_due": 7
    }
  ]
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `FinanceModels.swift` → `RecurringItemsResponse`, `RecurringItem` |
| n8n Workflow | `finance-planning-api.json` |
| DB Table | `finance.recurring_items` |
| DB View | `finance.upcoming_recurring` |
| Schema | `_schemas/nexus-recurring.json` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-recurring

Creates a recurring item.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "name": "Gym Membership",
  "amount": 300.00,
  "currency": "AED",
  "type": "expense",
  "cadence": "monthly",
  "day_of_month": 1,
  "category_id": 5,
  "merchant_pattern": "FITNESS FIRST",
  "auto_create": false,
  "notes": null
}
```

### Response

```json
{
  "success": true,
  "data": { "id": 5, "name": "Gym Membership", ... }
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `FinanceModels.swift` → `CreateRecurringItemRequest` |
| n8n Workflow | `finance-planning-api.json` |
| DB Table | `finance.recurring_items` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `CONFLICT`, `INTERNAL_ERROR`

---

## DELETE /webhook/nexus-recurring

Deletes a recurring item.

| Field | Value |
|-------|-------|
| Method | DELETE |
| Auth | X-API-Key header |
| Query Params | `id` (recurring item ID) |

### Delete Semantics

**SOFT DELETE** — Sets `is_active = false`. Row remains in `finance.recurring_items` for history.

### Response

```json
{
  "success": true,
  "message": "Recurring item deleted"
}
```

### Error Responses

`UNAUTHORIZED`, `NOT_FOUND`, `INTERNAL_ERROR`

---

## GET /webhook/nexus-rules

Fetches merchant matching rules.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |

### Response

```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "merchant_pattern": "CARREFOUR",
      "category": "Grocery",
      "is_grocery": true,
      "is_restaurant": false,
      "confidence": 100,
      "match_count": 45,
      "is_active": true
    }
  ]
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `FinanceModels.swift` → `MatchingRulesResponse`, `MatchingRule` |
| n8n Workflow | `finance-planning-api.json` |
| DB Table | `finance.merchant_rules` |
| Schema | `_schemas/nexus-rules.json` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## GET /webhook/nexus-monthly-trends

Fetches monthly spending trends.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |

### Response

```json
{
  "success": true,
  "data": {
    "monthly_spending": [
      {
        "month": "2026-02",
        "total_spent": 5000,
        "category_breakdown": {
          "Grocery": 1500,
          "Restaurant": 800,
          "Transport": 400
        }
      }
    ]
  }
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `FinanceModels.swift` → `MonthlyTrendsResponse`, `MonthlySpending` |
| n8n Workflow | `monthly-trends-webhook.json` |
| DB View | `finance.mv_monthly_spend` |
| Schema | `_schemas/nexus-monthly-trends.json` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## GET /webhook/nexus-financial-position

Fetches comprehensive financial position (net worth, accounts, upcoming payments).

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |

### Response

```json
{
  "success": true,
  "summary": {
    "total_assets": 50000,
    "total_liabilities": 5000,
    "net_worth": 45000,
    "upcoming_30d": 3500,
    "available_after_bills": 41500,
    "currency": "AED",
    "as_of": "2026-02-08"
  },
  "accounts": [
    {
      "id": 1,
      "name": "Emirates NBD",
      "institution": "Emirates NBD",
      "type": "checking",
      "balance": 25000,
      "currency": "AED",
      "is_liability": false
    }
  ],
  "upcoming_payments": [
    {
      "type": "recurring",
      "name": "DEWA",
      "amount": 570,
      "currency": "AED",
      "due_date": "2026-02-10",
      "days_until_due": 2,
      "urgency": "due_soon"
    }
  ],
  "monthly_obligations": {
    "recurring_total": 3500,
    "installments_total": 1200,
    "count": 15
  }
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `FinanceModels.swift` → `FinancialPositionResponse`, `AccountBalance`, `UpcomingPayment` |
| n8n Workflow | `financial-position-webhook.json` |
| DB Function | `finance.get_financial_position()` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-create-correction

Creates a transaction correction.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "transaction_id": 123,
  "amount": -30.00,
  "category": "Restaurant",
  "merchant_name": null,
  "date": null,
  "reason": "wrong_category",
  "notes": "Was miscategorized",
  "created_by": "ios_app"
}
```

### Response

```json
{
  "success": true,
  "correction_id": 45
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `FinanceModels.swift` → `CreateCorrectionRequest`, `CorrectionResponse` |
| n8n Workflow | `nexus-corrections-api.json` |
| DB Table | `finance.transaction_corrections` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `NOT_FOUND`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-trigger-import

Triggers SMS transaction import.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |
| Body | None |

### Response

```json
{
  "success": true,
  "message": "Import triggered",
  "imported": 5
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `FinanceAPI.swift` → `triggerImport()` |
| n8n Workflow | `trigger-sms-import.json` |
| DB Table | `finance.transactions` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-refresh-summary

Forces refresh of finance summary cache.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |
| Body | None |

### Response

```json
{
  "success": true,
  "message": "Summary refreshed"
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `FinanceAPI.swift` → `refreshSummary()` |
| n8n Workflow | `refresh-summary-webhook.json` |
| DB Function | `finance.refresh_financial_truth()` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## Notes

1. **Budget endpoints**: Two endpoints exist - `nexus-set-budget` (simple UPSERT) and `nexus-budgets` POST (full create request). Both are valid.
