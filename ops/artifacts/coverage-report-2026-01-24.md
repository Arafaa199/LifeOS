# SMS Coverage Report - 2026-01-24

## Executive Summary

| Metric | Value |
|--------|-------|
| Status | 🔴 CRITICAL |
| Assessment | Many transactions missing |
| Capture Rate | 89.7% |
| Total Financial SMS | 29 |
| Transactions Created | 26 |
| Missing | 3 |
| Days Tracked | 16 |
| Period | Thu Dec 25 2025 00:00:00 GMT+0400 (Gulf Standard Time) to Thu Jan 15 2026 00:00:00 GMT+0400 (Gulf Standard Time) |

---

## Coverage Gaps


| Date | Status | Financial SMS | Captured | Missing |
|------|--------|---------------|----------|---------|
| 2026-01-15 | MINOR_GAP | 2 | 0 | 2 |
| 2026-01-11 | MINOR_GAP | 3 | 2 | 1 |


---

## Raw Event Resolution

| Status | Count | Oldest | Newest |
|--------|-------|--------|--------|
| pending | 14 | Sat Jan 24 2026 00:00:00 GMT+0400 (Gulf Standard Time) | Sat Jan 24 2026 00:00:00 GMT+0400 (Gulf Standard Time) |
| linked | 7 | Sat Jan 24 2026 00:00:00 GMT+0400 (Gulf Standard Time) | Sat Jan 24 2026 00:00:00 GMT+0400 (Gulf Standard Time) |

---

## Pattern Performance

| Pattern | Count | Created TX | Avg Confidence |
|---------|-------|------------|----------------|
| debit_purchase | 23 | 23 | 0.95 |
| order_refund | 3 | 0 | 0.95 |
| transfer_outgoing | 1 | 1 | 0.95 |
| credit_card_payment | 1 | 1 | 0.95 |
| salary_deposit | 1 | 1 | 0.99 |

---

## Sender Breakdown

| Sender | Total | Financial | Captured | Rate |
|--------|-------|-----------|----------|------|
| EmiratesNBD | 34 | 26 | 26 | 100% |
| CAREEM | 4 | 3 | 0 | 0% |
| Apple | 1 | 0 | 0 | 0% |

---

## Recommendations


### Action Items

1. **Investigate missing transactions** - Check `raw.sms_missing_transactions` view
2. **Review pattern matching** - Some SMS may not match expected patterns
3. **Check import logs** - Look for errors in `~/Cyber/Infrastructure/Nexus-setup/logs/`


---

*Generated: 2026-01-24T20:35:51.791Z*
*Report covers last 30 days of SMS data*
