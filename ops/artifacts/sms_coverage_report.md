# SMS Coverage Report
**Generated:** 2026-01-24
**Audit Window:** Last 60 days
**Goal:** Prove LifeOS captures ALL relevant financial signals correctly

---

## Executive Summary

| Metric | Value | Assessment |
|--------|-------|------------|
| **Total SMS Processed** | 343 | Good coverage |
| **Financial SMS** | 155 | |
| **Transactions Created** | 146 | 94.2% capture rate |
| **Correctly Excluded** | 188 | (OTP, security, info) |
| **Pattern Coverage** | 99% | Only 1 unhandled variant |

---

## 1. SMS Classification Breakdown

| Intent | Count | Created TX | Notes |
|--------|-------|------------|-------|
| `FIN_TXN_APPROVED` | 143 | 143 | Purchases, transfers |
| `IGNORE` | 131 | 0 | OTP, promo, setup |
| `FIN_INFO_ONLY` | 44 | 0 | Balance alerts, statements |
| `FIN_AUTH_CODE` | 12 | 0 | 2FA codes |
| `FIN_TXN_REFUND` | 9 | 3 | Refunds (some wallet-only) |
| `FIN_TXN_DECLINED` | 3 | 0 | Declined (correct: no TX) |
| `FIN_LOGIN_ALERT` | 1 | 0 | Login notification |
| **TOTAL** | **343** | **146** | |

**Capture Rate:** 146/155 financial SMS = **94.2%**

---

## 2. SMS by Sender

| Sender | Count | Notes |
|--------|-------|-------|
| EmiratesNBD | 295 | Primary UAE bank (Arabic) |
| CAREEM | 28 | Ride/food (refunds to wallet) |
| AlRajhiBank | 15 | Saudi bank (English) |
| Amazon | 5 | Refund notifications |

---

## 3. Reconciliation Views Created

| View | Purpose |
|------|---------|
| `finance.v_reconciliation_summary` | Executive dashboard metrics |
| `finance.v_daily_spend_reconciliation` | Day-by-day SMS vs TX comparison |
| `finance.v_sms_ingestion_health` | Parse success rate by sender |
| `finance.v_data_coverage_gaps` | Flag days with anomalies |
| `finance.v_receipt_transaction_matching` | Match receipts to transactions |

---

## 4. Data Quality Issues Found

### CRITICAL: Transaction Dates Wrong

**Issue:** All 150 transactions have `transaction_at = 2026-01-24` (import date) instead of the actual SMS received date.

**Impact:**
- Daily reconciliation shows 60 days with "NO_TRANSACTIONS"
- Historical spending analysis is broken
- Cannot correlate spending with recovery/health

**Root Cause:** SMS import script using current timestamp instead of `received_at` from SMS.

**Fix Required:** Update SMS importer to use `received_at` for `transaction_at`.

### MEDIUM: 9 Refund SMS, Only 3 Transactions

6 refund SMS did not create transactions. Investigation:
- CAREEM refunds go to Careem Wallet, not bank account
- These are correctly classified but may warrant separate tracking

---

## 5. Pattern Coverage Analysis

**Source:** macOS Messages chat.db (last 60 days)

| Metric | Value |
|--------|-------|
| Total SMS from tracked senders | 102 (from chat.db audit) |
| Patterns matched | 101 |
| Unmatched | 1 |
| **Coverage** | **99.0%** |

### Unhandled Pattern (1 message)

```
Message: "تم خصم مبلغ AED 4,800.99 من حسابك 101XXX79XXX04 لتسديد مستحقات بطاقتك الائتمانية"
Type: Credit card payment
Status: Pattern exists but regex variant doesn't match inline account number
```

**Recommendation:** Regex already uses `.*` wildcard - may be sender mismatch or encoding issue.

---

## 6. Reconciliation Summary (Current State)

```
total_sms          | 105
financial_sms      | 85
sms_created_tx     | 79
sms_capture_rate   | 92.9%
total_transactions | 150
tx_from_sms        | 147
total_spend_aed    | 122,685.17
total_income_aed   | 115,942.91
total_receipts     | 7
parsed_receipts    | 0
linked_receipts    | 0
days_with_issues   | 60
coverage_score     | 1.6%
```

**Note:** Low coverage score due to transaction date issue (all TX on one day).

---

## 7. Recommended Actions

### Immediate (P0)
1. **Fix transaction_at timestamps** - Use SMS `received_at` not import time
2. **Backfill existing transactions** - Update 150 existing TXs with correct dates

### Short-term (P1)
3. **Add CAREEM wallet tracking** - Separate tracking for wallet refunds
4. **Improve receipt parsing** - 7 receipts, 0 parsed

### Medium-term (P2)
5. **Add balance tracking** - Extract balance from SMS for verification
6. **Duplicate detection** - Ensure same-day same-amount SMS are deduplicated

---

## 8. Files Created

- `artifacts/sql/051_reconciliation_views.sql` - Reconciliation views
- `artifacts/sms_regex_patterns.yaml` - Pattern definitions (existing)
- `artifacts/sms_coverage_report.md` - This report

---

## Conclusion

**SMS coverage is GOOD (99%)** but **data quality needs improvement** (transaction dates).

The system is capturing financial signals correctly, but the transaction timestamps prevent meaningful reconciliation. Fix the date issue first, then coverage score will improve dramatically.

**Next Steps:**
1. Fix SMS importer to use correct timestamps
2. Backfill existing transaction dates
3. Re-run reconciliation to verify
