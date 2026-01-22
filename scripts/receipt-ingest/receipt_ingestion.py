#!/usr/bin/env python3
"""
Receipt Ingestion System for Nexus

Fetches receipts from Gmail, parses PDFs, and stores in database.
Currently supports: Carrefour UAE

Usage:
    ./receipt_ingestion.py --fetch           # Fetch new receipts from Gmail
    ./receipt_ingestion.py --parse           # Parse pending receipts
    ./receipt_ingestion.py --link            # Link receipts to transactions
    ./receipt_ingestion.py --all             # Do all of the above

Environment variables:
    NEXUS_DB_HOST, NEXUS_DB_USER, NEXUS_DB_PASS, NEXUS_DB_NAME
    GMAIL_CREDENTIALS_PATH
"""

import os
import sys
import json
import hashlib
import argparse
import base64
import re
from datetime import datetime, date
from pathlib import Path
from typing import Optional, Dict, Any, List, Tuple

import psycopg2
from psycopg2.extras import RealDictCursor

# Gmail API
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from google.auth.transport.requests import Request
from googleapiclient.discovery import build

# PDF parsing
from pypdf import PdfReader
import io
import subprocess

# Local parsers
from carrefour_parser import parse_carrefour_receipt, validate_parsed_receipt, PARSE_VERSION


# ============================================================================
# Configuration
# ============================================================================

GMAIL_SCOPES = ['https://www.googleapis.com/auth/gmail.readonly']
GMAIL_LABEL = os.environ.get('GMAIL_LABEL', 'LifeOS/Receipts/Carrefour')

# PDF storage - configurable for server deployment
_default_pdf_path = Path.home() / 'Cyber/Infrastructure/Nexus-setup/data/receipts'
PDF_STORAGE_PATH = Path(os.environ.get('PDF_STORAGE_PATH', str(_default_pdf_path)))

# Database config (can be overridden by env vars)
DB_CONFIG = {
    'host': os.environ.get('NEXUS_HOST', '100.90.189.16'),
    'port': os.environ.get('NEXUS_PORT', '5432'),
    'database': os.environ.get('NEXUS_DB', 'nexus'),
    'user': os.environ.get('NEXUS_USER', 'nexus'),
    'password': os.environ.get('NEXUS_PASSWORD', ''),
}

# Secrets/credentials paths - configurable for server deployment
SCRIPT_DIR = Path(__file__).parent
SECRETS_DIR = Path(os.environ.get('SECRETS_DIR', str(SCRIPT_DIR)))
CREDENTIALS_PATH = SECRETS_DIR / 'gmail_client_secret.json'
TOKEN_PATH = SECRETS_DIR / 'token.pickle'


# ============================================================================
# Database Connection
# ============================================================================

def get_db_connection():
    """Get PostgreSQL database connection."""
    return psycopg2.connect(**DB_CONFIG)


# ============================================================================
# Gmail Integration
# ============================================================================

def get_gmail_service():
    """Authenticate and return Gmail API service."""
    import pickle

    creds = None

    # Load existing token from pickle
    if TOKEN_PATH.exists():
        with open(TOKEN_PATH, 'rb') as token_file:
            creds = pickle.load(token_file)

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
            # Save refreshed token
            with open(TOKEN_PATH, 'wb') as token_file:
                pickle.dump(creds, token_file)
        else:
            if not CREDENTIALS_PATH.exists():
                print(f"Error: Gmail credentials not found at {CREDENTIALS_PATH}")
                print("Download OAuth credentials from Google Cloud Console")
                sys.exit(1)

            flow = InstalledAppFlow.from_client_secrets_file(
                str(CREDENTIALS_PATH), GMAIL_SCOPES
            )
            creds = flow.run_local_server(port=0)

            # Save token as pickle
            with open(TOKEN_PATH, 'wb') as token_file:
                pickle.dump(creds, token_file)

    return build('gmail', 'v1', credentials=creds)


def get_label_id(service, label_name: str) -> Optional[str]:
    """Get Gmail label ID by name."""
    results = service.users().labels().list(userId='me').execute()
    for label in results.get('labels', []):
        if label['name'] == label_name:
            return label['id']
    return None


def fetch_receipts_from_gmail(service, label_id: str, conn) -> Tuple[int, int, int]:
    """Fetch receipt emails from Gmail label.

    Returns: (messages_processed, pdfs_saved, messages_skipped)
    """
    messages_processed = 0
    pdfs_saved = 0
    messages_skipped = 0

    # Get messages with the specified label (paginate to get all)
    page_token = None
    all_messages = []

    while True:
        results = service.users().messages().list(
            userId='me',
            labelIds=[label_id],
            maxResults=100,
            pageToken=page_token
        ).execute()

        all_messages.extend(results.get('messages', []))
        page_token = results.get('nextPageToken')
        if not page_token:
            break

    print(f"Found {len(all_messages)} messages in label")

    for msg_info in all_messages:
        msg_id = msg_info['id']

        # Check if already processed (any receipt with this message ID)
        with conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) FROM finance.receipts WHERE gmail_message_id = %s",
                (msg_id,)
            )
            existing_count = cur.fetchone()[0]
            if existing_count > 0:
                print(f"  Skipping message {msg_id[:8]}... (already has {existing_count} receipt(s))")
                messages_skipped += 1
                continue

        # Get full message
        msg = service.users().messages().get(
            userId='me', id=msg_id, format='full'
        ).execute()

        saved = process_gmail_message(service, msg, conn)
        if saved:
            messages_processed += 1
            pdfs_saved += len(saved)

    return messages_processed, pdfs_saved, messages_skipped


def process_gmail_message(service, msg: Dict, conn) -> List[Dict]:
    """Process a single Gmail message, extract ALL PDF attachments.

    Returns list of saved receipts (one per PDF).
    """
    headers = {h['name'].lower(): h['value'] for h in msg['payload']['headers']}

    msg_id = msg['id']
    thread_id = msg['threadId']
    internal_date = msg.get('internalDate')  # Unix timestamp in ms
    from_addr = headers.get('from', '')
    subject = headers.get('subject', '')

    # Convert internalDate to datetime
    if internal_date:
        email_received_at = datetime.fromtimestamp(int(internal_date) / 1000)
    else:
        date_str = headers.get('date', '')
        email_received_at = parse_email_date(date_str)

    print(f"Processing: {subject[:60]}...")

    # Find ALL PDF attachments
    pdfs_found = []

    def find_pdfs_in_parts(parts):
        for part in parts:
            mime_type = part.get('mimeType', '')
            if mime_type == 'application/pdf' or (mime_type == 'application/octet-stream' and part.get('filename', '').lower().endswith('.pdf')):
                attachment_id = part.get('body', {}).get('attachmentId')
                if attachment_id:
                    try:
                        attachment = service.users().messages().attachments().get(
                            userId='me', messageId=msg_id, id=attachment_id
                        ).execute()
                        pdf_data = base64.urlsafe_b64decode(attachment['data'])
                        pdf_filename = part.get('filename', 'receipt.pdf')
                        pdfs_found.append((pdf_filename, pdf_data))
                    except Exception as e:
                        print(f"  Error downloading attachment: {e}")
            if 'parts' in part:
                find_pdfs_in_parts(part['parts'])

    if 'parts' in msg['payload']:
        find_pdfs_in_parts(msg['payload']['parts'])

    if not pdfs_found:
        print(f"  No PDF attachments found")
        return []

    print(f"  Found {len(pdfs_found)} PDF(s)")

    saved_receipts = []

    for pdf_filename, pdf_data in pdfs_found:
        # Calculate PDF hash
        pdf_hash = hashlib.sha256(pdf_data).hexdigest()

        # Check for duplicate by hash
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id FROM finance.receipts WHERE pdf_hash = %s",
                (pdf_hash,)
            )
            if cur.fetchone():
                print(f"    Skipping {pdf_filename} (duplicate PDF hash)")
                continue

        # Save PDF to storage
        PDF_STORAGE_PATH.mkdir(parents=True, exist_ok=True)
        safe_filename = re.sub(r'[^\w\-.]', '_', pdf_filename)
        pdf_path = PDF_STORAGE_PATH / f"{pdf_hash[:16]}_{safe_filename}"
        pdf_path.write_bytes(pdf_data)

        # Determine vendor from label (ingestion only - no PDF parsing)
        vendor = 'carrefour_uae'  # We know this from the label

        # Insert receipt record (metadata only, no parsing)
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO finance.receipts (
                    gmail_message_id, gmail_thread_id, gmail_label,
                    email_from, email_subject, email_received_at,
                    pdf_hash, pdf_filename, pdf_size_bytes, pdf_storage_path,
                    vendor, parse_status
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'pending')
                RETURNING id
            """, (
                msg_id, thread_id, GMAIL_LABEL,
                from_addr, subject, email_received_at,
                pdf_hash, pdf_filename, len(pdf_data), str(pdf_path.relative_to(PDF_STORAGE_PATH.parent)),
                vendor
            ))
            receipt_id = cur.fetchone()[0]
            conn.commit()

        print(f"    Saved: ID {receipt_id}, {pdf_filename} ({len(pdf_data)} bytes)")

        saved_receipts.append({
            'id': receipt_id,
            'pdf_path': pdf_path,
            'pdf_hash': pdf_hash,
            'filename': pdf_filename,
            'size': len(pdf_data)
        })

    return saved_receipts


def parse_email_date(date_str: str) -> datetime:
    """Parse email date header to datetime."""
    # Common email date formats
    formats = [
        '%a, %d %b %Y %H:%M:%S %z',
        '%d %b %Y %H:%M:%S %z',
        '%a, %d %b %Y %H:%M:%S %Z',
    ]

    # Remove parenthesized timezone names like (PST)
    date_str = re.sub(r'\s*\([^)]+\)\s*$', '', date_str)

    for fmt in formats:
        try:
            return datetime.strptime(date_str, fmt)
        except ValueError:
            continue

    # Fallback to now
    return datetime.now()


def identify_vendor(from_addr: str, subject: str, pdf_data: bytes) -> str:
    """Identify vendor from email metadata and PDF content."""
    text = from_addr.lower() + ' ' + subject.lower()

    # Extract some PDF text for identification
    try:
        reader = PdfReader(io.BytesIO(pdf_data))
        if reader.pages:
            pdf_text = reader.pages[0].extract_text().lower()
            text += ' ' + pdf_text[:1000]
    except:
        pass

    if 'carrefour' in text or 'maf retail' in text or 'majid al futtaim' in text:
        return 'carrefour_uae'

    return 'unknown'


# ============================================================================
# PDF Parsing
# ============================================================================

def parse_pending_receipts(conn) -> int:
    """Parse all pending receipts."""
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute("""
            SELECT id, vendor, pdf_storage_path, pdf_hash
            FROM finance.receipts
            WHERE parse_status = 'pending'
            ORDER BY created_at
        """)
        pending = cur.fetchall()

    print(f"Found {len(pending)} receipts to parse")

    parsed_count = 0
    for receipt in pending:
        success = parse_receipt(conn, receipt)
        if success:
            parsed_count += 1

    return parsed_count


def parse_receipt(conn, receipt: Dict) -> bool:
    """Parse a single receipt based on vendor."""
    receipt_id = receipt['id']
    vendor = receipt['vendor']

    # Resolve PDF path
    pdf_path = PDF_STORAGE_PATH.parent / receipt['pdf_storage_path']
    if not pdf_path.exists():
        mark_parse_failed(conn, receipt_id, f"PDF not found: {pdf_path}")
        return False

    print(f"Parsing receipt {receipt_id} (vendor: {vendor})")

    # Extract raw text using pdftotext with layout preservation
    try:
        result = subprocess.run(
            ['pdftotext', '-layout', str(pdf_path), '-'],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0:
            raise Exception(f"pdftotext failed: {result.stderr}")
        raw_text = result.stdout
    except Exception as e:
        mark_parse_failed(conn, receipt_id, f"PDF text extraction error: {e}")
        return False

    # Store raw text
    with conn.cursor() as cur:
        cur.execute("""
            INSERT INTO finance.receipt_raw_text (receipt_id, raw_text, extraction_method)
            VALUES (%s, %s, 'pdftotext_layout')
            ON CONFLICT (receipt_id) DO UPDATE SET
                raw_text = EXCLUDED.raw_text,
                created_at = NOW()
        """, (receipt_id, raw_text))

    # Parse based on vendor
    if vendor == 'carrefour_uae':
        return parse_carrefour_uae(conn, receipt_id, raw_text, str(pdf_path))
    else:
        mark_parse_failed(conn, receipt_id, f"Unknown vendor: {vendor}")
        return False


def parse_carrefour_uae(conn, receipt_id: int, raw_text: str, pdf_path: str = None) -> bool:
    """Parse Carrefour UAE receipt format using dedicated parser module."""
    try:
        # Use the carrefour_parser module
        parsed = parse_carrefour_receipt(raw_text)

        # Check if document should be skipped (tips, refunds, etc.)
        if parsed.get('skip_reason'):
            doc_type = parsed.get('doc_type', 'unknown')
            mark_parse_skipped(conn, receipt_id, doc_type, parsed['skip_reason'])
            return True  # Not a failure, just skipped

        # Validate parsed data
        validation_errors = validate_parsed_receipt(parsed)
        if validation_errors:
            parsed['validation_errors'] = validation_errors

        # Check for critical parse errors
        if parsed.get('parse_errors') and not parsed.get('invoice_no'):
            mark_parse_failed(conn, receipt_id, f"Parse errors: {parsed['parse_errors']}")
            return False

        # Extract key fields
        invoice_number = parsed.get('invoice_no')
        store_name = parsed.get('store_name', 'Carrefour')
        total_amount = parsed.get('total_incl_vat')
        vat_amount = parsed.get('vat_amount')
        subtotal = parsed.get('total_excl_vat')
        template_hash = parsed.get('template_hash')
        parse_version = parsed.get('parse_version', PARSE_VERSION)

        # Parse date from invoice_date (format: YYYY-MM-DD)
        receipt_date = None
        if parsed.get('invoice_date'):
            try:
                receipt_date = datetime.strptime(parsed['invoice_date'], '%Y-%m-%d').date()
            except ValueError:
                pass

        # =====================================================================
        # Template Drift Detection
        # =====================================================================
        # Check if this template_hash is known/approved
        is_known_template = False
        if template_hash:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT id, status FROM finance.receipt_templates
                    WHERE template_hash = %s
                """, (template_hash,))
                template_row = cur.fetchone()

                if template_row:
                    # Template exists - check if approved
                    is_known_template = (template_row[1] == 'approved')
                else:
                    # New template - register it as needs_review
                    cur.execute("""
                        INSERT INTO finance.receipt_templates
                            (vendor, template_hash, parse_version, sample_receipt_id, status, notes)
                        VALUES ('carrefour_uae', %s, %s, %s, 'needs_review', 'Auto-detected new template')
                        ON CONFLICT (template_hash) DO NOTHING
                    """, (template_hash, parse_version, receipt_id))
                    print(f"  New template detected: {template_hash[:16]}...")

        # If template is not approved, mark for review and skip item insertion
        if template_hash and not is_known_template:
            with conn.cursor() as cur:
                cur.execute("""
                    UPDATE finance.receipts SET
                        invoice_number = %s,
                        store_name = %s,
                        receipt_date = %s,
                        subtotal = %s,
                        vat_amount = %s,
                        total_amount = %s,
                        template_hash = %s,
                        parse_version = %s,
                        parsed_json = %s,
                        parse_status = 'needs_review',
                        parse_error = 'Unknown template - awaiting approval',
                        parsed_at = NOW(),
                        updated_at = NOW()
                    WHERE id = %s
                """, (
                    invoice_number, store_name, receipt_date,
                    subtotal, vat_amount, total_amount,
                    template_hash, parse_version,
                    json.dumps(parsed, ensure_ascii=False),
                    receipt_id
                ))
            conn.commit()
            print(f"  Needs review: unknown template, {len(parsed.get('line_items', []))} items parsed but not inserted")
            return True  # Not a failure, just needs review

        # Update receipt record with parsed data
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE finance.receipts SET
                    invoice_number = %s,
                    store_name = %s,
                    receipt_date = %s,
                    subtotal = %s,
                    vat_amount = %s,
                    total_amount = %s,
                    template_hash = %s,
                    parse_version = %s,
                    parsed_json = %s,
                    parse_status = 'success',
                    parsed_at = NOW(),
                    updated_at = NOW()
                WHERE id = %s
            """, (
                invoice_number, store_name, receipt_date,
                subtotal, vat_amount, total_amount,
                template_hash, parse_version,
                json.dumps(parsed, ensure_ascii=False),
                receipt_id
            ))

        # Delete existing line items (for re-parsing)
        with conn.cursor() as cur:
            cur.execute("DELETE FROM finance.receipt_items WHERE receipt_id = %s", (receipt_id,))

        # Insert parsed line items
        line_items = parsed.get('line_items', [])
        items_sum = 0.0
        with conn.cursor() as cur:
            for idx, item in enumerate(line_items, 1):
                line_total = item.get('total_incl_vat', 0) or 0
                items_sum += line_total
                cur.execute("""
                    INSERT INTO finance.receipt_items (
                        receipt_id, line_number, item_code, item_description,
                        item_description_clean, quantity, unit_price,
                        line_total, discount_amount, is_promotional
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    receipt_id,
                    idx,
                    item.get('barcode'),
                    item.get('description'),
                    clean_item_description(item.get('description', '')),
                    item.get('qty_delivered', 1),
                    item.get('unit_price_incl_vat'),
                    line_total,
                    item.get('discount', 0),
                    item.get('voucher_discount') is not None
                ))

        # Reconciliation check: verify items sum matches total
        reconciliation_tolerance = 0.10  # 10 fils
        if total_amount and abs(items_sum - total_amount) > reconciliation_tolerance:
            with conn.cursor() as cur:
                cur.execute("""
                    UPDATE finance.receipts SET
                        parse_status = 'needs_review',
                        parse_error = %s,
                        updated_at = NOW()
                    WHERE id = %s
                """, (
                    f"Reconciliation failed: items sum {items_sum:.2f} != total {total_amount:.2f} (diff: {abs(items_sum - total_amount):.2f})",
                    receipt_id
                ))
            conn.commit()
            print(f"  Needs review: items sum {items_sum:.2f} != total {total_amount:.2f}")
            return True  # Not a failure, just needs review

        conn.commit()
        print(f"  Parsed: {len(line_items)} items, total: {total_amount} AED (verified)")
        return True

    except Exception as e:
        import traceback
        mark_parse_failed(conn, receipt_id, f"{e}\n{traceback.format_exc()}")
        return False


def parse_carrefour_line_items(raw_text: str) -> List[Dict]:
    """Parse Carrefour receipt line items."""
    items = []

    # Pattern for line items: Description followed by price
    # Carrefour format varies but typically:
    # ITEM NAME                    XX.XX
    # or
    # QTY x ITEM NAME              XX.XX

    lines = raw_text.split('\n')

    # Find the section between items and totals
    in_items = False

    for i, line in enumerate(lines):
        line = line.strip()

        # Skip header/metadata lines
        if any(x in line.upper() for x in ['INVOICE', 'TRN:', 'CARREFOUR', 'TAX', 'TOTAL', 'SUBTOTAL', 'CHANGE', 'CASH', 'CARD']):
            if 'TOTAL' in line.upper() and in_items:
                break  # End of items
            continue

        # Look for price at end of line
        price_match = re.search(r'([\d,]+\.?\d*)\s*$', line)
        if price_match and len(line) > 10:
            price_str = price_match.group(1)
            try:
                price = float(price_str.replace(',', ''))
                if 0.01 <= price <= 10000:  # Reasonable item price range
                    description = line[:price_match.start()].strip()
                    if description and len(description) > 2:
                        in_items = True

                        # Check for quantity prefix
                        qty_match = re.match(r'^(\d+)\s*[xX@]\s*(.+)', description)
                        if qty_match:
                            qty = int(qty_match.group(1))
                            desc = qty_match.group(2)
                            unit_price = price / qty if qty > 0 else price
                        else:
                            qty = 1
                            desc = description
                            unit_price = price

                        items.append({
                            'description': desc,
                            'quantity': qty,
                            'unit_price': unit_price,
                            'total': price,
                            'is_promo': 'PROMO' in description.upper() or 'OFFER' in description.upper()
                        })
            except (ValueError, TypeError):
                continue

    return items


def clean_item_description(desc: str) -> str:
    """Normalize item description for matching."""
    # Remove extra whitespace
    desc = ' '.join(desc.split())
    # Remove special characters
    desc = re.sub(r'[^\w\s]', ' ', desc)
    # Uppercase
    desc = desc.upper()
    return desc.strip()


def mark_parse_failed(conn, receipt_id: int, error: str):
    """Mark receipt parsing as failed."""
    with conn.cursor() as cur:
        cur.execute("""
            UPDATE finance.receipts SET
                parse_status = 'failed',
                parse_error = %s,
                updated_at = NOW()
            WHERE id = %s
        """, (error, receipt_id))
    conn.commit()
    print(f"  Parse failed: {error}")


def mark_parse_skipped(conn, receipt_id: int, doc_type: str, reason: str):
    """Mark receipt as skipped (not a parsing failure, just unsupported doc type)."""
    with conn.cursor() as cur:
        cur.execute("""
            UPDATE finance.receipts SET
                parse_status = 'skipped',
                doc_type = %s,
                parse_error = %s,
                parsed_at = NOW(),
                updated_at = NOW()
            WHERE id = %s
        """, (doc_type, reason, receipt_id))
    conn.commit()
    print(f"  Skipped: {doc_type} - {reason}")


# ============================================================================
# Transaction Creation (for receipts without SMS)
# ============================================================================

def create_transaction_for_receipt(conn, receipt: Dict) -> Optional[int]:
    """
    Create a finance.transactions record for a receipt that has no linked SMS transaction.

    Uses client_id = 'receipt:<pdf_hash>' for idempotency.

    Returns: transaction_id if created, None if already exists or error
    """
    receipt_id = receipt['id']
    pdf_hash = receipt['pdf_hash']
    total_amount = receipt['total_amount']
    receipt_date = receipt['receipt_date']
    store_name = receipt.get('store_name', 'Carrefour')

    # Generate idempotent client_id from PDF hash
    # varchar(36) limit: "rcpt:" (5) + 31 hex chars = 36
    client_id = f"rcpt:{pdf_hash[:31]}"

    # Check if transaction already exists (idempotency)
    with conn.cursor() as cur:
        cur.execute("""
            SELECT id FROM finance.transactions
            WHERE client_id = %s
        """, (client_id,))
        existing = cur.fetchone()
        if existing:
            print(f"  Transaction already exists for receipt {receipt_id}: txn {existing[0]}")
            # Link the receipt if not already linked
            cur.execute("""
                UPDATE finance.receipts
                SET linked_transaction_id = %s, updated_at = NOW()
                WHERE id = %s AND linked_transaction_id IS NULL
            """, (existing[0], receipt_id))
            conn.commit()
            return existing[0]

    # Create transaction
    # Schema: date, merchant_name, amount, currency, category, is_grocery, client_id, notes
    with conn.cursor() as cur:
        cur.execute("""
            INSERT INTO finance.transactions (
                date,
                merchant_name,
                amount,
                currency,
                category,
                is_grocery,
                client_id,
                notes
            ) VALUES (
                %s,
                %s,
                %s,
                'AED',
                'Grocery',
                true,
                %s,
                %s
            )
            RETURNING id
        """, (
            receipt_date,
            f"Carrefour {store_name}" if store_name else 'Carrefour',
            -abs(total_amount),  # Expenses are negative
            client_id,
            f"Auto-created from receipt #{receipt_id}"
        ))
        txn_id = cur.fetchone()[0]

    # Link receipt to the new transaction
    with conn.cursor() as cur:
        cur.execute("""
            UPDATE finance.receipts
            SET linked_transaction_id = %s, updated_at = NOW()
            WHERE id = %s
        """, (txn_id, receipt_id))

    conn.commit()
    print(f"  Created transaction {txn_id} for receipt {receipt_id} ({total_amount} AED)")
    return txn_id


def create_transactions_for_unlinked_receipts(conn) -> int:
    """Create transactions for all unlinked receipts that don't match SMS."""
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute("""
            SELECT r.id, r.pdf_hash, r.receipt_date, r.total_amount, r.store_name
            FROM finance.receipts r
            WHERE r.linked_transaction_id IS NULL
              AND r.parse_status = 'success'
              AND r.total_amount IS NOT NULL
            ORDER BY r.receipt_date DESC
        """)
        unlinked = cur.fetchall()

    print(f"Found {len(unlinked)} unlinked receipts")

    created_count = 0
    for receipt in unlinked:
        # First try to link to existing transaction
        receipt_id = receipt['id']
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT * FROM finance.find_matching_transaction(%s)", (receipt_id,))
            matches = cur.fetchall()

        if matches:
            # Link to existing SMS transaction
            match = matches[0]
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT finance.link_receipt_to_transaction(%s, %s, %s, %s)
                """, (receipt_id, match['transaction_id'], match['match_type'], match['confidence']))
            conn.commit()
            print(f"  Linked receipt {receipt_id} to existing txn {match['transaction_id']}")
        else:
            # No SMS match - create new transaction from receipt
            txn_id = create_transaction_for_receipt(conn, receipt)
            if txn_id:
                created_count += 1

    return created_count


# ============================================================================
# Transaction Linkage
# ============================================================================

def link_receipts_to_transactions(conn) -> int:
    """Attempt to link unlinked receipts to transactions."""
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute("""
            SELECT id, receipt_date, total_amount, store_name
            FROM finance.receipts
            WHERE linked_transaction_id IS NULL
              AND parse_status = 'success'
              AND total_amount IS NOT NULL
            ORDER BY receipt_date DESC
        """)
        unlinked = cur.fetchall()

    print(f"Found {len(unlinked)} unlinked receipts")

    linked_count = 0
    for receipt in unlinked:
        receipt_id = receipt['id']

        # Use the DB function to find match
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("""
                SELECT * FROM finance.find_matching_transaction(%s)
            """, (receipt_id,))
            matches = cur.fetchall()

        if matches:
            match = matches[0]
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT finance.link_receipt_to_transaction(%s, %s, %s, %s)
                """, (
                    receipt_id,
                    match['transaction_id'],
                    match['match_type'],
                    match['confidence']
                ))
            conn.commit()

            print(f"  Linked receipt {receipt_id} to transaction {match['transaction_id']} "
                  f"({match['match_type']}, confidence: {match['confidence']})")
            linked_count += 1
        else:
            print(f"  No match for receipt {receipt_id} "
                  f"(date: {receipt['receipt_date']}, amount: {receipt['total_amount']})")

    return linked_count


# ============================================================================
# Main
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description='Nexus Receipt Ingestion')
    parser.add_argument('--fetch', action='store_true', help='Fetch receipts from Gmail')
    parser.add_argument('--parse', action='store_true', help='Parse pending receipts')
    parser.add_argument('--link', action='store_true', help='Link receipts to transactions')
    parser.add_argument('--create-transactions', action='store_true',
                        help='Create transactions for unlinked receipts')
    parser.add_argument('--all', action='store_true', help='Do all operations')
    parser.add_argument('--label', default=GMAIL_LABEL, help='Gmail label to monitor')
    parser.add_argument('--receipt-id', type=int, help='Parse specific receipt by ID')
    parser.add_argument('--reparse', action='store_true', help='Re-parse even if already parsed')
    parser.add_argument('--approve-template', type=str, metavar='HASH',
                        help='Approve a template hash for drift detection')
    parser.add_argument('--report-drift', action='store_true',
                        help='Report receipts needing review (drift/reconciliation issues)')

    args = parser.parse_args()

    if not any([args.fetch, args.parse, args.link, args.create_transactions,
                args.all, args.receipt_id, args.approve_template, args.report_drift]):
        parser.print_help()
        return

    # Check database password - load from .env if not set
    if not DB_CONFIG['password']:
        env_path = Path.home() / 'Cyber/Infrastructure/Nexus-setup/.env'
        if env_path.exists():
            for line in env_path.read_text().splitlines():
                if line.startswith('NEXUS_PASSWORD='):
                    DB_CONFIG['password'] = line.split('=', 1)[1].strip()
                    break

    conn = get_db_connection()

    try:
        if args.fetch or args.all:
            print("\n=== Fetching receipts from Gmail ===")
            print(f"Label: {args.label}")
            service = get_gmail_service()
            label_id = get_label_id(service, args.label)

            if not label_id:
                print(f"Error: Label '{args.label}' not found in Gmail")
                print("Available labels:")
                results = service.users().labels().list(userId='me').execute()
                for label in sorted(results.get('labels', []), key=lambda x: x['name']):
                    print(f"  - {label['name']}")
                return

            print(f"Label ID: {label_id}")
            messages_processed, pdfs_saved, messages_skipped = fetch_receipts_from_gmail(service, label_id, conn)

            print(f"\n=== Ingestion Summary ===")
            print(f"Messages processed: {messages_processed}")
            print(f"PDFs saved: {pdfs_saved}")
            print(f"Messages skipped (already ingested): {messages_skipped}")

            # Report database counts
            with conn.cursor() as cur:
                cur.execute("SELECT COUNT(*) FROM finance.receipts")
                total_receipts = cur.fetchone()[0]
                cur.execute("SELECT COUNT(DISTINCT pdf_hash) FROM finance.receipts")
                unique_pdfs = cur.fetchone()[0]
                cur.execute("SELECT SUM(pdf_size_bytes) FROM finance.receipts")
                total_size = cur.fetchone()[0] or 0
            print(f"\nDatabase totals:")
            print(f"  Total receipts: {total_receipts}")
            print(f"  Unique PDFs: {unique_pdfs}")
            print(f"  Total storage: {total_size / 1024 / 1024:.2f} MB")

        if args.receipt_id:
            print(f"\n=== Parsing specific receipt ID: {args.receipt_id} ===")
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                status_filter = "" if args.reparse else "AND parse_status = 'pending'"
                cur.execute(f"""
                    SELECT id, vendor, pdf_storage_path, pdf_hash, parse_status
                    FROM finance.receipts
                    WHERE id = %s {status_filter}
                """, (args.receipt_id,))
                receipt = cur.fetchone()

            if not receipt:
                # Check if receipt exists but is already parsed
                with conn.cursor(cursor_factory=RealDictCursor) as cur:
                    cur.execute("SELECT id, parse_status FROM finance.receipts WHERE id = %s", (args.receipt_id,))
                    existing = cur.fetchone()
                if existing:
                    print(f"Receipt {args.receipt_id} already has parse_status='{existing['parse_status']}'")
                    print("Use --reparse to force re-parsing")
                else:
                    print(f"Receipt {args.receipt_id} not found")
                return

            # Reset status for re-parsing
            if args.reparse and receipt['parse_status'] != 'pending':
                with conn.cursor() as cur:
                    cur.execute("""
                        UPDATE finance.receipts SET parse_status = 'pending', parse_error = NULL
                        WHERE id = %s
                    """, (args.receipt_id,))
                conn.commit()

            success = parse_receipt(conn, receipt)
            print(f"Parse {'succeeded' if success else 'failed'}")
            return

        if args.parse or args.all:
            print("\n=== Parsing pending receipts ===")
            parsed = parse_pending_receipts(conn)
            print(f"Parsed {parsed} receipts")

        if args.link or args.all:
            print("\n=== Linking receipts to transactions ===")
            linked = link_receipts_to_transactions(conn)
            print(f"Linked {linked} receipts")

        if args.create_transactions or args.all:
            print("\n=== Creating transactions for unlinked receipts ===")
            created = create_transactions_for_unlinked_receipts(conn)
            print(f"Created {created} transactions")

        if args.approve_template:
            print(f"\n=== Approving template: {args.approve_template} ===")
            with conn.cursor() as cur:
                cur.execute("""
                    UPDATE finance.receipt_templates
                    SET status = 'approved', notes = COALESCE(notes, '') || ' - Manually approved'
                    WHERE template_hash = %s OR template_hash LIKE %s
                    RETURNING template_hash, vendor
                """, (args.approve_template, args.approve_template + '%'))
                result = cur.fetchone()
                if result:
                    print(f"Approved template {result[0][:16]}... for vendor {result[1]}")
                    # Re-parse any receipts that were waiting on this template
                    cur.execute("""
                        SELECT id FROM finance.receipts
                        WHERE template_hash = %s AND parse_status = 'needs_review'
                    """, (result[0],))
                    pending = cur.fetchall()
                    if pending:
                        print(f"Re-parsing {len(pending)} receipts with this template...")
                        for (rid,) in pending:
                            cur.execute("""
                                UPDATE finance.receipts SET parse_status = 'pending'
                                WHERE id = %s
                            """, (rid,))
                        conn.commit()
                        parse_pending_receipts(conn)
                else:
                    print(f"Template not found: {args.approve_template}")
                conn.commit()

        if args.report_drift:
            print("\n=== Drift/Review Report ===")
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                # Report receipts needing review
                cur.execute("""
                    SELECT r.id, r.receipt_date, r.total_amount, r.store_name,
                           r.parse_status, r.parse_error, r.template_hash
                    FROM finance.receipts r
                    WHERE r.parse_status = 'needs_review'
                    ORDER BY r.created_at DESC
                """)
                needs_review = cur.fetchall()

                if needs_review:
                    print(f"\nReceipts needing review ({len(needs_review)}):")
                    for r in needs_review:
                        print(f"  ID {r['id']}: {r['receipt_date']} {r['store_name']} "
                              f"${r['total_amount']:.2f} - {r['parse_error'][:60]}...")
                else:
                    print("\nNo receipts needing review.")

                # Report unknown templates
                cur.execute("""
                    SELECT template_hash, vendor, status, first_seen_at,
                           (SELECT COUNT(*) FROM finance.receipts WHERE template_hash = t.template_hash) as receipt_count
                    FROM finance.receipt_templates t
                    WHERE status != 'approved'
                    ORDER BY first_seen_at DESC
                """)
                unknown_templates = cur.fetchall()

                if unknown_templates:
                    print(f"\nUnknown/unapproved templates ({len(unknown_templates)}):")
                    for t in unknown_templates:
                        print(f"  {t['template_hash'][:16]}... vendor={t['vendor']} "
                              f"status={t['status']} receipts={t['receipt_count']}")
                else:
                    print("\nAll templates approved.")

    finally:
        conn.close()


if __name__ == '__main__':
    main()
