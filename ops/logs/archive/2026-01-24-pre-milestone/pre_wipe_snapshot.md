# TASK-090 Pre-Wipe Snapshot
**Generated:** 2026-01-24 04:00 UTC

## Row Counts Before Wipe

| Table | Row Count |
|-------|-----------|
| finance.transactions | 1194 |
| finance.receipts | 25 |
| finance.receipt_items | 90 |
| finance.raw_events | 83 |
| finance.budgets | 21 |
| finance.categories | 16 |
| finance.merchant_rules | 133 |
| finance.recurring_items | 11 |
| raw.bank_sms | 0 |
| raw.github_events | 37 |
| health.whoop_recovery | 5 |
| health.whoop_sleep | 5 |
| health.metrics | 2 |
| facts.daily_summary | 1 |
| facts.daily_finance | 1 |
| facts.daily_health | 1 |
| insights.daily_finance_summary | 2 |
| insights.weekly_reports | 1 |
| ops.pipeline_alerts | 6 |
| ops.feed_status | 5 |
| life.locations | 6 |
| life.behavioral_events | 2 |
| life.daily_facts | 10 |
| normalized.transactions | 0 |

## Notes
- Reference data (budgets, categories, merchant_rules, recurring_items) will NOT be wiped
- Only transactional/derived data will be truncated
- raw.bank_sms is already 0 (SMS stored elsewhere or already processed)
