# Nexus Documentation

## Current Documentation

See the main [README.md](../README.md) for:
- Quick start guide
- Database schema
- n8n integration
- Backup/restore commands

## n8n Workflows

See [n8n-workflows/README.md](../n8n-workflows/README.md) for webhook documentation.

## Key Webhooks

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/webhook/nexus-food` | POST | Food logging |
| `/webhook/nexus-water` | POST | Water logging |
| `/webhook/nexus-weight` | POST | Weight from HealthKit |
| `/webhook/nexus-expense` | POST | Quick expense (with client_id) |
| `/webhook/nexus-transaction` | POST | Add transaction (with client_id) |
| `/webhook/nexus-income` | POST | Add income (with client_id) |
| `/webhook/nexus-sleep` | GET | WHOOP sleep/recovery |
| `/webhook/nexus-finance-summary` | GET | Finance overview |
| `/webhook/nexus-dashboard-today` | GET | Unified dashboard payload |
| `/webhook/nexus-categories` | GET/POST | CRUD categories |
| `/webhook/nexus-recurring` | GET/POST | CRUD recurring items |
| `/webhook/nexus-rules` | GET/POST | CRUD matching rules |

## Health Data Flow

```
WHOOP → Home Assistant → n8n (health-metrics-sync) → health.metrics
Eufy Scale → Apple Health → iOS App → /webhook/nexus-weight → health.metrics
```

## Finance System (Jan 2026)

### Tables
- `finance.transactions` - All transactions with `transaction_at TIMESTAMPTZ`
- `finance.categories` - 16 default categories
- `finance.recurring_items` - Bills and recurring income
- `finance.merchant_rules` - Auto-categorization rules (120+)
- `finance.budgets` - Monthly budgets per category

### Timezone Handling (Migration 011)
```sql
-- Single source of truth for business date derivation
SELECT finance.to_business_date(transaction_at) AS business_date;
-- Equivalent to: (transaction_at AT TIME ZONE 'Asia/Dubai')::date

-- Get current business date
SELECT finance.current_business_date();
```

### Auto-Categorization
Trigger `categorize_transaction()` fires on INSERT/UPDATE:
- Matches `merchant_name` against `merchant_rules.pattern`
- Sets `category`, `match_rule_id`, `match_reason`, `match_confidence`
- Fallback: "Uncategorized" with `match_reason='no_match'`

### Idempotency
All finance creates support `client_id` (UUID from iOS):
- `UNIQUE INDEX idx_transactions_client_id WHERE client_id IS NOT NULL`
- n8n uses `ON CONFLICT (client_id) DO NOTHING`

## Migrations

| Migration | Description |
|-----------|-------------|
| 009 | Add `client_id` for idempotency |
| 010 | Finance planning (categories, recurring, rules, auto-categorize trigger) |
| 011 | Timezone consistency (`transaction_at TIMESTAMPTZ`, `to_business_date()`) |

## Archived Docs

Historical deployment/setup docs compressed in `_archive.tar.gz` (25 files, ~80KB).
Extract if needed: `tar -xzvf _archive.tar.gz`

Contents: deployment guides, MCP server design, finance setup, backend assessments (Jan 2026).
