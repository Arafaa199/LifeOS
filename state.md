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
- **Repo**: `https://github.com/Arafaa199/Nexus-setup.git`

### Deployment Model
- ✅ Repo connected and pushed to GitHub
- ✅ Server deployed via `deploy-to-server.sh` (private repo, no server git access)
- ✅ Timer running: `OnCalendar=hourly` with 5min randomized delay
- ✅ Linger enabled: `sudo loginctl enable-linger scrypt` (timer persists after logout)

### Environment Configuration

| Location | File | Purpose |
|----------|------|---------|
| Mac | `.env.local` | Local dev credentials (gitignored) |
| Server | `~/lifeos/secrets/nexus.env` | Production credentials (chmod 600) |

**Variables:**
```
NEXUS_DB_HOST=100.90.189.16  # Mac uses Tailscale IP
NEXUS_DB_HOST=127.0.0.1      # Server uses localhost
NEXUS_DB_PORT=5432
NEXUS_DB_NAME=nexus
NEXUS_DB_USER=nexus
NEXUS_PASSWORD=<in secrets>
NEXUS_TZ=Asia/Dubai
```

**Systemd wiring:**
```ini
# ~/.config/systemd/user/receipt-ingest.service
[Service]
EnvironmentFile=%h/lifeos/secrets/nexus.env
```

**Rule:** Never commit passwords. `.env.local` stays local.

### Contracts (Externalized)

Ingestion contracts moved from Claude Coder state.md to standalone docs:

| Contract | File | Purpose |
|----------|------|---------|
| SMS Transactions | `docs/contracts/sms-transactions.md` | Bank SMS → PostgreSQL |
| Receipts | `docs/contracts/receipts.md` | Gmail → PDF storage + parsing |
| Ledger | `docs/contracts/ledger.md` | Unified financial view |
| Vendors | `docs/contracts/vendors.md` | Adding new receipt vendors |

---

## Production Status

| System | Status | Verified |
|--------|--------|----------|
| SMS Transactions | **PROD** | 2026-01-22 |
| SMS Income/Salary | **PROD** | 2026-01-22 |
| Gmail Receipts | **PROD** | 2026-01-22 |

---

## Database Migrations

### Migration 016: Cleanup Stale Pending Events (2026-01-22)

**Applied:** 2026-01-22

**Purpose:** Marks events stuck in 'pending' validation status as 'failed' after 5 minutes (workflow timeout)

**Function Created:**
```sql
CREATE OR REPLACE FUNCTION finance.cleanup_stale_pending_events()
RETURNS INTEGER AS $$
DECLARE
  updated_count INTEGER;
BEGIN
  UPDATE finance.raw_events
  SET validation_status = 'failed',
      validation_errors = ARRAY['workflow_timeout']
  WHERE validation_status = 'pending'
    AND created_at < NOW() - INTERVAL '5 minutes';

  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RETURN updated_count;
END;
$$ LANGUAGE plpgsql;
```

**Usage:**
```sql
-- Manual cleanup
SELECT finance.cleanup_stale_pending_events();

-- Check for stuck events
SELECT id, event_type, client_id, created_at, NOW() - created_at as age
FROM finance.raw_events
WHERE validation_status = 'pending'
ORDER BY created_at DESC;
```

**Scheduling:**
- ✅ **Deployed**: `Nexus: Cleanup Stale Events` workflow (ID: V7XV6WoZtZ4U5o0Y)
- ✅ **Active**: Runs hourly via n8n schedule trigger
- File: `n8n-workflows/cleanup-stale-events.json`

---

### Migration 015: Raw Events Audit Table (2026-01-22)

**Applied:** 2026-01-22

**Purpose:** Audit trail for all incoming finance events (webhooks, SMS, etc.)

**Table Created:**
```sql
CREATE TABLE finance.raw_events (
    id SERIAL PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL,      -- 'income_webhook', 'sms_import', etc.
    raw_payload JSONB NOT NULL,           -- Full raw payload from source
    client_id VARCHAR(36),                 -- Client ID for correlation
    source_identifier VARCHAR(200),        -- SMS sender, IP, etc.
    parsed_amount NUMERIC(10,2),          -- Server-parsed amount
    parsed_currency VARCHAR(3),            -- Server-parsed currency
    validation_status VARCHAR(20),         -- 'valid', 'invalid', 'duplicate'
    validation_errors TEXT[],              -- Array of validation errors
    related_transaction_id INTEGER,        -- FK to transactions if created
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

**Indexes:**
- `event_type` - Query by event source
- `client_id` (partial) - Correlation lookups
- `created_at DESC` - Recent events first
- `validation_status` - Filter by validation result

**Usage:**
```sql
-- Today's income webhook events
SELECT event_type, validation_status, COUNT(*)
FROM finance.raw_events
WHERE created_at >= CURRENT_DATE
  AND event_type = 'income_webhook'
GROUP BY event_type, validation_status;

-- Failed validations with errors
SELECT raw_payload, validation_errors
FROM finance.raw_events
WHERE validation_status = 'invalid'
ORDER BY created_at DESC
LIMIT 10;

-- Duplicate detection rate
SELECT
  COUNT(*) FILTER (WHERE validation_status = 'duplicate') as duplicates,
  COUNT(*) FILTER (WHERE validation_status = 'valid') as unique_inserts
FROM finance.raw_events
WHERE event_type = 'income_webhook';
```

---

### Migration 014: client_id Full Unique Index (2026-01-22)

**Applied:** 2026-01-22

**Issue:** Partial unique index `WHERE client_id IS NOT NULL` doesn't support `ON CONFLICT` in PostgreSQL

**Solution:** Convert to full unique index (NULL values still allowed, only non-NULL must be unique)

**Changes:**
```sql
DROP INDEX finance.idx_transactions_client_id;  -- Partial index
CREATE UNIQUE INDEX idx_transactions_client_id
  ON finance.transactions (client_id);          -- Full index
```

**Idempotency Test (Replay Proof):**
```sql
-- Test 1: Initial insert
INSERT INTO finance.transactions (..., client_id)
VALUES (..., 'test-salary-uuid-12345678901234')
ON CONFLICT (client_id) DO NOTHING
RETURNING id;
-- Result: id=6768, INSERT 0 1

-- Test 2: REPLAY same insert (idempotency test)
INSERT INTO finance.transactions (..., client_id)
VALUES (..., 'test-salary-uuid-12345678901234')
ON CONFLICT (client_id) DO NOTHING
RETURNING id;
-- Result: (0 rows), INSERT 0 0  ✅ IDEMPOTENT - no duplicate created

-- Verification
SELECT COUNT(*) FROM finance.transactions
WHERE client_id = 'test-salary-uuid-12345678901234';
-- Result: 1 row (only the first insert exists)
```

---

### Migration 013: Finance Defaults and Timestamp Clarity (2026-01-22)

**Applied:** 2026-01-22

**Changes:**
1. **client_id unique index** - Already existed from migration 009 (later fixed in 014)
2. **Currency default** - Changed from USD → AED (Dubai Dirham)
3. **Timestamp documentation** - Clarified created_at vs transaction_at

**Verification:**
```sql
-- ✅ 1. client_id unique index exists
SELECT indexdef FROM pg_indexes
WHERE schemaname = 'finance' AND tablename = 'transactions'
  AND indexname LIKE '%client_id%';
-- Result: CREATE UNIQUE INDEX idx_transactions_client_id ON finance.transactions
--         USING btree (client_id) WHERE (client_id IS NOT NULL)

-- ✅ 2. Currency default is AED
SELECT column_default FROM information_schema.columns
WHERE table_schema = 'finance' AND table_name = 'transactions'
  AND column_name = 'currency';
-- Result: 'AED'::character varying

-- ✅ 3. No NULL currencies
SELECT COUNT(*) FROM finance.transactions
WHERE currency IS NULL OR currency = '';
-- Result: 0

-- ✅ 4. Currency distribution
SELECT currency, COUNT(*) FROM finance.transactions
GROUP BY currency ORDER BY COUNT(*) DESC;
-- Result: SAR(365), AED(80), BHD(26), JOD(24), EGP(4), USD(3), GBP(1)

-- ✅ 5. Column comments exist
SELECT col_description('finance.transactions'::regclass, attnum) as comment, attname
FROM pg_attribute
WHERE attrelid = 'finance.transactions'::regclass
  AND attname IN ('created_at', 'transaction_at');
-- Result: Comments correctly document created_at (non-authoritative)
--         vs transaction_at (authoritative)
```

**Timestamp Policy:**
- `created_at` (timestamp without time zone) - Non-authoritative, record insertion time for debugging
- `transaction_at` (timestamp with time zone) - **AUTHORITATIVE**, use for all business logic
- Use `finance.to_business_date(transaction_at)` for date aggregations

---

## Trigger Architecture

| Component | Trigger | Location | Idempotency Key |
|-----------|---------|----------|-----------------|
| SMS Transactions | Event-driven (fswatch) | Mac | `sms-{md5(sender\|date\|text)[:16]}` |
| SMS Income/Salary (PRIMARY) | Event-driven (fswatch) | Mac | `sms-{md5(sender\|date\|text)[:16]}` |
| **Income Webhook (FALLBACK)** | **Manual POST** | **n8n** | **`client_id` (UUID from client)** |
| Gmail Receipts | Hourly (systemd timer) | nexus server | `pdf_hash` (SHA256) |

### Income Ingestion: Primary vs Fallback

**Primary Source: SMS (PROD)**
- Real-time: Seconds after bank SMS arrives
- Auto-triggered: fswatch on `~/Library/Messages/chat.db`
- Idempotency: MD5 hash of SMS content
- Risk: Requires Mac powered on (mitigated by 15-min fallback cron)

**Fallback Source: Webhook (PROD-SAFE)**
- Manual: Requires explicit POST request
- Use case: Manual salary entry if SMS fails, bonus payments, cash income
- Idempotency: `client_id` UUID enforced by unique index + `ON CONFLICT DO NOTHING`
- Endpoint: `POST https://n8n.rfanw/webhook/nexus-income`

**Webhook Parameters:**
```json
{
  "client_id": "uuid-v4-from-ios-app",
  "transaction_at": "2026-01-22T09:00:00+04:00",
  "source": "Emirates NBD Salary",
  "amount": 23500.00,
  "currency": "AED",
  "category": "Income",
  "notes": "January salary",
  "is_recurring": true
}
```

**Authentication:**
```bash
# Required header
X-API-Key: 3f62259deac4aa96427ba0048c3addfe1924f872586d8371d6adfb3d2db3afd8

# Example curl
curl -X POST https://n8n.rfanw/webhook/nexus-income \
  -H "Content-Type: application/json" \
  -H "X-API-Key: 3f62259deac4aa96427ba0048c3addfe1924f872586d8371d6adfb3d2db3afd8" \
  -d '{
    "client_id": "550e8400-e29b-41d4-a716-446655440000",
    "transaction_at": "2026-01-22T09:00:00+04:00",
    "source": "Emirates NBD Salary",
    "amount": 23500.00,
    "currency": "AED",
    "category": "Income",
    "notes": "January salary",
    "is_recurring": true
  }'
```

**Production Safety:**
- ✅ Idempotent: Replay-safe via `client_id` unique constraint (migration 014)
- ✅ Timezone-aware: Uses `transaction_at` (TIMESTAMPTZ)
- ✅ Business date: Auto-derived via `finance.to_business_date(transaction_at)`
- ✅ Tested: Migration 014 replay test proves idempotency at DB level
- ✅ Authenticated: Requires `X-API-Key` header (same key as iOS app)

**✅ Deployment Status (2026-01-22):**

The validated income webhook with server-side parsing and audit logging is **DEPLOYED AND TESTED**.

**Active Workflow:** `Nexus - Add Income Webhook (Validated)` (ID: WcAZz2Jkzt1sqOX9)

**Inactive/Old Workflows (Archive in UI):**
- `Nexus - Add Income Webhook` (ID: URXBr7WEztRMfqsN) - Simple version without validation
- `Nexus - Add Income Webhook` (ID: jwgl7hAx0hOK3oC9) - Duplicate
- `Nexus - Add Income Webhook` (ID: MH7FDoqFy1slCPXPJEJSf) - Duplicate
- `Nexus - Add Income Webhook (Validated)` (ID: qbxXgmkto4N8k53N) - Old version with bug
- `Nexus - Add Income Webhook (Validated)` (ID: Vh3fMD0hzTgjTavk) - Old version with bug

**Features:**
- ✅ Server-side amount/currency parsing from `raw_text` field
- ✅ Full audit trail in `finance.raw_events`
- ✅ Client-side validation rejection (missing `client_id`)
- ✅ Idempotency proven (same `client_id` creates only 1 transaction)
- ✅ Stale event cleanup (hourly via `Nexus: Cleanup Stale Events` workflow)

**Test Results (2026-01-22, Final Fixed Version):**

✅ **Test 1: New Transaction** (client_id: `test-final-valid-1769107341`)
- Payload: `{"amount": 7500, "currency": "AED", ...}`
- Result: Transaction created (ID 7018)
- Audit: `validation_status='valid'`, `related_transaction_id=7018`, `parsed_amount=7500.00`

✅ **Test 2: Duplicate (Replay)**
- Same client_id posted again
- Result: NO new transaction, raw_event logged
- Audit: `validation_status='duplicate'`, `related_transaction_id=NULL`, `parsed_amount=7500.00`
- Verified: 2 raw_events, 1 transaction (idempotent)

✅ **Test 3: Raw Text Parsing** (client_id: `test-raw-text-*`)
- Payload: `{"raw_text": "Emirates NBD: Salary credit of 25,750.50 AED received", ...}` (NO `amount` field)
- Server parsed: "25,750.50 AED" → amount=25750.50, currency='AED'

**Workflow Fix (2026-01-22):**
- Added "Compute Insert Result" code node after Insert Transaction
- Added "Was Inserted?" IF node to branch on insert success
- Separate UPDATE nodes: "Mark Valid" (true) and "Mark Duplicate" (false)
- Now properly sets `validation_status` and `related_transaction_id`

**Automated Cleanup:**
- Workflow: `Nexus: Cleanup Stale Events` (ID: V7XV6WoZtZ4U5o0Y)
- File: `n8n-workflows/cleanup-stale-events.json`
- Schedule: Hourly
- Action: Marks events stuck in 'pending' >5 minutes as 'failed'
- Function: `finance.cleanup_stale_pending_events()`
- ✅ **Parse error handling** - Invalid amounts/currencies rejected with error details

**Current Status:**
- ✅ Migration 015 applied - `finance.raw_events` table created
- ✅ Workflow created - `income-webhook-validated.json`
- ⚠️ Manual activation required - Deploy via n8n UI (automated CLI activation failed)

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
| Restaurant transactions | 25 |
| Food-related transactions | 46 |
| Grocery transactions | 21 |
| Restaurant merchant rules | 44 |

**Rules added (2026-01-22):** VESUVIO, SOCIAL CLUB, BUTCHER, GRILL, STEAKHOUSE, POPEYES, HARDEES, WENDYS, TACO BELL, DUNKIN, CARIBOU, INSTASHOP, CAREEM NOW

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
