# Receipt Ingestion System

Automated receipt ingestion for Nexus finance tracking.

## Setup

### 1. Gmail API Credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing
3. Enable the Gmail API:
   - Go to APIs & Services → Library
   - Search for "Gmail API"
   - Click Enable
4. Create OAuth credentials:
   - Go to APIs & Services → Credentials
   - Click "Create Credentials" → "OAuth client ID"
   - Application type: "Desktop app"
   - Name: "Nexus Receipt Ingestion"
   - Download the JSON file
5. Save as `credentials.json` in this directory

### 2. Create Gmail Label

Create a label in Gmail called `Receipts/Carrefour` (or customize via `--label` flag).

Forward or move Carrefour receipt emails to this label.

### 3. Environment Variables

The script reads from `~/Cyber/Infrastructure/Nexus-setup/.env`:

```bash
NEXUS_HOST=100.90.189.16
NEXUS_USER=nexus
NEXUS_DB=nexus
NEXUS_PASSWORD=your-password
```

Or set in shell: `export NEXUS_PASSWORD="your-password"`

### 4. First Run (OAuth Flow)

```bash
./run-receipt-ingest.sh --fetch
```

This will open a browser for Google OAuth. Authorize the app.
Token is saved to `token.json` for future runs.

## Usage

```bash
# Fetch new receipts from Gmail
./run-receipt-ingest.sh --fetch

# Parse pending receipts (extract data from PDFs)
./run-receipt-ingest.sh --parse

# Link receipts to finance transactions
./run-receipt-ingest.sh --link

# Do all of the above
./run-receipt-ingest.sh --all

# Use different Gmail label
./run-receipt-ingest.sh --fetch --label "Finance/Receipts"
```

## Supported Vendors

- **Carrefour UAE** - Full support (PDF text parsing)

## Data Flow

```
Gmail (labeled emails)
    ↓
PDF Attachments
    ↓ (stored by SHA256 hash)
finance.receipts (metadata)
    ↓ (text extraction)
finance.receipt_raw_text
    ↓ (vendor-specific parsing)
finance.receipt_items (line items)
    ↓ (matching)
finance.transactions (linked)
```

## Idempotency

Duplicate prevention at three levels:
1. `gmail_message_id` - Same email won't be processed twice
2. `pdf_hash` - Same PDF content won't be stored twice
3. `invoice_number` - Can detect duplicate receipts

## Database Tables

- `finance.receipts` - Receipt metadata, totals, linkage
- `finance.receipt_items` - Parsed line items
- `finance.receipt_raw_text` - Raw extracted text
- `finance.receipt_parsers` - Vendor parser configs

## Files

- `receipt_ingestion.py` - Main ingestion script
- `run-receipt-ingest.sh` - Runner with venv activation
- `credentials.json` - Gmail OAuth credentials (you provide)
- `token.json` - OAuth token (auto-generated)
- `.venv/` - Python virtual environment

## Adding New Vendors

1. Add vendor patterns to `finance.receipt_parsers` table
2. Create `parse_<vendor>()` function in `receipt_ingestion.py`
3. Update `identify_vendor()` to detect the vendor
