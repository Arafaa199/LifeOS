# Nexus Finance Ingestion - Project State

## Deployment Summary

### Server Runtime (Production)
- **Server**: nexus (100.90.189.16)
- **User**: scrypt
- **Base Path**: `~/lifeos/`

| Path | Purpose |
|------|---------|
| `~/lifeos/receipt-ingest/` | Application code + Docker |
| `~/lifeos/secrets/` | Gmail OAuth credentials |
| `~/lifeos/data/receipts/` | PDF storage (hash-based) |
| `~/lifeos/logs/` | Application logs |

### Mac (Development Only)
- **Path**: `~/Cyber/Infrastructure/Nexus-setup/scripts/receipt-ingest/`
- **Purpose**: Code development, deploy to server via `deploy-to-server.sh`

---

## Production Status

| System | Status | Verified |
|--------|--------|----------|
| SMS Transactions | **PROD** | 2026-01-22 |
| SMS Income/Salary | **PROD** | 2026-01-22 |
| Gmail Receipts | **PROD** | 2026-01-22 |

---

## Trigger Architecture

| Component | Trigger | Location | Idempotency Key |
|-----------|---------|----------|-----------------|
| SMS Transactions | Event-driven (fswatch) | Mac | `sms-{md5(sender\|date\|text)[:16]}` |
| SMS Income/Salary | Event-driven (fswatch) | Mac | `sms-{md5(sender\|date\|text)[:16]}` |
| Gmail Receipts | Hourly (systemd timer) | nexus server | `pdf_hash` (SHA256) |

---

## Income Ingestion Decision (2026-01-22)

**Status: PROD**

| Question | Answer |
|----------|--------|
| Is income triggered automatically? | **YES** - fswatch on chat.db |
| Trigger source? | **SMS** (Emirates NBD, AlRajhi, JKB) |
| Idempotency key? | `sms-{md5(sender\|date\|text)[:16]}` |

### SMS Income: PROD Classification

| Criteria | Status |
|----------|--------|
| Event-driven | ✅ fswatch (seconds latency) |
| Idempotent | ✅ MD5 hash + ON CONFLICT |
| Fallback | ✅ 15-min scheduled import |
| Running | ✅ PID active, processing events |

**Risk:** Mac must be on for real-time. Mitigated by:
- Messages queue in iCloud, sync on wake
- 15-minute fallback catches missed events
- No alternative exists (banks don't email real-time)

**Exit Plan (if needed):** None required. SMS is the only real-time source for bank transactions. Email statements are batch/delayed and would be additive, not replacement.

---

## Manual Commands

```bash
# SSH to server
ssh nexus

# One-time manual run (all operations)
cd ~/lifeos/receipt-ingest
docker compose run --rm receipt-ingest --all

# Individual operations
docker compose run --rm receipt-ingest --fetch   # Gmail ingestion
docker compose run --rm receipt-ingest --parse   # PDF parsing
docker compose run --rm receipt-ingest --link    # Transaction linking

# Check timer status
systemctl --user list-timers | grep receipt

# View logs
cat ~/lifeos/logs/receipt-ingest.log
journalctl --user -u receipt-ingest -f
```

---

## Verification Output (2026-01-22)

```
Receipts by status and doc_type:
 parse_status |   doc_type   | count
--------------+--------------+-------
 skipped      | tips_receipt |     4
 success      | tax_invoice  |     8

Linked receipts: 2
Line items: 76
Total storage: 1.37 MB
```

---

## Idempotency Verification

Re-running `--fetch` correctly skips already-ingested messages:
```
Found 8 messages in label
  Skipping message 19bdd1c8... (already has 1 receipt(s))
  Skipping message 19bd0244... (already has 2 receipt(s))
  ...
Messages processed: 0
Messages skipped (already ingested): 8
```

---

## Deployment Steps (for future reference)

### Initial Setup
```bash
# From Mac
cd ~/Cyber/Infrastructure/Nexus-setup/scripts/receipt-ingest
./deploy-to-server.sh

# Or manual:
ssh nexus "mkdir -p ~/lifeos/{receipt-ingest,secrets,data/receipts,logs}"
scp carrefour_parser.py receipt_ingestion.py nexus:~/lifeos/receipt-ingest/
scp deploy/* nexus:~/lifeos/receipt-ingest/
scp gmail_client_secret.json token.pickle nexus:~/lifeos/secrets/
```

### Build & Test
```bash
ssh nexus
cd ~/lifeos/receipt-ingest
docker compose build
docker compose run --rm receipt-ingest --all
```

### Enable Timer
```bash
ssh nexus
systemctl --user daemon-reload
systemctl --user enable --now receipt-ingest.timer
```

---

## Document Types

| doc_type | parse_status | Description |
|----------|--------------|-------------|
| tax_invoice | success | Standard grocery receipts |
| tips_receipt | skipped | Driver tip receipts |
| refund_note | skipped | Refund documents |

---

## Files Modified

- `carrefour_parser.py` - Added `detect_document_type()`, `doc_type` field
- `receipt_ingestion.py` - Added `mark_parse_skipped()`, configurable paths
- `deploy/` - Docker + systemd files for server deployment
- Database: Added `doc_type` column, `skipped` parse_status

---

## Data Reset (2026-01-22)

One-time dummy data reset performed:

| Action | Count |
|--------|-------|
| Manual/test transactions deleted | 290 |
| SMS transactions preserved | 503 |
| Receipts preserved | 12 |
| Receipt items preserved | 76 |
| scheduled_payments cleared | 2 |

**Post-reset verification:**
```
Transactions: 503 (all SMS-imported)
  - Income: 22 (including 2 salary @ 23,500 AED)
  - Expense: 481
Receipts: 12 (8 parsed, 4 skipped)
Reference tables: accounts(3), merchant_rules(120), categories(16)
```

**Idempotency verified:**
- Receipt fetch: 8 messages skipped (already ingested)
- SMS import: 0 new, 3 skipped (non-transaction)

---

## Restaurant/Card-Only Classification (2026-01-22)

| Metric | Count |
|--------|-------|
| Restaurant transactions | 23 |
| Grocery transactions | 21 |
| Card-only (no receipt) | 503 |

**How it works:**
- `merchant_rules` table stores patterns with `is_restaurant`, `is_food_related` flags
- SMS import applies rules automatically via `LIKE` pattern matching
- Receipts link to transactions via `linked_transaction_id`

**Flags:**
| Flag | Purpose |
|------|---------|
| `is_restaurant` | Card-only restaurant spend (delivery, dining) |
| `is_food_related` | Any food spend (includes grocery) |
| `is_grocery` | Grocery stores specifically |

**Query examples:**
```sql
-- Restaurant card-only spend
SELECT merchant_name, amount FROM finance.transactions
WHERE is_restaurant = true;

-- Food without receipts
SELECT t.* FROM finance.transactions t
LEFT JOIN finance.receipts r ON r.linked_transaction_id = t.id
WHERE t.is_food_related = true AND r.id IS NULL;
```

---

## Design Notes

- `docs/event-driven-finance-ingestion.md` - Receipt ingestion architecture
- `docs/income-ingestion-audit.md` - Income/salary audit findings

---

*Last updated: 2026-01-22*
