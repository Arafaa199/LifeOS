"""
Carrefour UAE Receipt Parser v1

Extracts structured data from Carrefour UAE PDF receipts.

Output format:
{
    "invoice_no": "83707162",
    "invoice_date": "2026-01-21",
    "order_no": "784030013456096",
    "store_name": "Marina Silverene",
    "total_incl_vat": 161.00,
    "total_excl_vat": 153.33,
    "vat_amount": 7.67,
    "vat_rate": 5.0,
    "currency": "AED",
    "payment_method": "Apple Pay",
    "line_items": [
        {
            "description": "Almarai Low Fat Fresh Milk, 1L",
            "barcode": "6281007040419",
            "qty_ordered": 1.0,
            "qty_delivered": 1.0,
            "unit_price_incl_vat": 5.19,
            "unit_price_excl_vat": 4.94,
            "total_excl_vat": 4.94,
            "vat_rate": 5.0,
            "vat_amount": 0.25,
            "discount": 0.00,
            "total_incl_vat": 5.19
        },
        ...
    ],
    "savings": {
        "promo_savings": 1.02,
        "product_savings": 0.54,
        "total_savings": 1.56
    }
}
"""

import re
from datetime import datetime
from typing import Dict, List, Optional, Any
from pathlib import Path


def detect_document_type(pdf_text: str) -> str:
    """
    Detect the type of Carrefour document.

    Returns:
        'tax_invoice' - Standard grocery receipt
        'tips_receipt' - Driver tip receipt
        'refund_note' - Refund document
        'unknown' - Unrecognized format
    """
    text_lower = pdf_text.lower()

    # Check tax_invoice FIRST - takes priority since PDFs may contain
    # generic "Refund Note" policy sections in the footer
    if 'tax invoice' in text_lower:
        return 'tax_invoice'
    if 'tips receipt' in text_lower or 'driver tip' in text_lower:
        return 'tips_receipt'
    if 'refund note' in text_lower or 'credit note' in text_lower:
        return 'refund_note'

    return 'unknown'


def parse_carrefour_receipt(pdf_text: str) -> Dict[str, Any]:
    """
    Parse Carrefour UAE receipt text into structured data.

    Args:
        pdf_text: Raw text extracted from PDF

    Returns:
        Dictionary with parsed receipt data

    Raises:
        ValueError: If critical fields cannot be extracted
    """
    # Detect document type first
    doc_type = detect_document_type(pdf_text)

    result = {
        "parser_version": "1.0.0",
        "vendor": "carrefour_uae",
        "doc_type": doc_type,
        "parse_errors": [],
        "line_items": [],
        "savings": {}
    }

    # Skip non-invoice documents (tips, refunds) - mark for skipping
    if doc_type != 'tax_invoice':
        result["skip_reason"] = f"Document type '{doc_type}' not supported for parsing"
        return result

    # Clean the text - remove Arabic (RTL) text for easier parsing
    # Keep only ASCII and common Unicode
    lines = pdf_text.split('\n')

    # =========================================================================
    # Extract Invoice Metadata
    # =========================================================================

    # The Carrefour PDF has labels and values on separate lines:
    # Invoice No.
    # : 83707162
    # Or sometimes inline: Invoice No. : 83707162

    # Find all lines starting with ": " which are values
    # The order after the header block is typically:
    # Order No, Invoice No, Order Date, Invoice Date, Exp. Del. Date
    colon_values = re.findall(r'^:\s*(.+)$', pdf_text, re.MULTILINE)

    # Also try inline patterns
    # Invoice No (try multiple patterns)
    invoice_match = re.search(r'Invoice No\.?\s*[:.]?\s*(\d{8,})', pdf_text)
    if invoice_match:
        result["invoice_no"] = invoice_match.group(1)
    else:
        # Look for 8-digit numbers in colon values (invoice numbers are 8 digits)
        for val in colon_values:
            if re.match(r'^\d{8}$', val.strip()):
                result["invoice_no"] = val.strip()
                break
        if "invoice_no" not in result:
            result["parse_errors"].append("Could not extract invoice_no")

    # Order No (15+ digit numbers)
    order_match = re.search(r'Order No\.?\s*[:.]?\s*(\d{12,})', pdf_text)
    if order_match:
        result["order_no"] = order_match.group(1)
    else:
        for val in colon_values:
            if re.match(r'^\d{12,}$', val.strip()):
                result["order_no"] = val.strip()
                break

    # Invoice Date (format: DD-Mon-YYYY)
    date_match = re.search(r'Invoice Date\s*[:.]?\s*(\d{1,2}-[A-Za-z]{3}-\d{4})', pdf_text)
    if date_match:
        try:
            date_str = date_match.group(1)
            parsed_date = datetime.strptime(date_str, '%d-%b-%Y')
            result["invoice_date"] = parsed_date.strftime('%Y-%m-%d')
        except ValueError:
            result["parse_errors"].append(f"Could not parse date: {date_str}")
    else:
        # Look for date pattern in colon values
        for val in colon_values:
            date_pattern = re.match(r'^(\d{1,2}-[A-Za-z]{3}-\d{4})', val.strip())
            if date_pattern:
                try:
                    parsed_date = datetime.strptime(date_pattern.group(1), '%d-%b-%Y')
                    result["invoice_date"] = parsed_date.strftime('%Y-%m-%d')
                    break
                except ValueError:
                    continue
        if "invoice_date" not in result:
            result["parse_errors"].append("Could not extract invoice_date")

    # Store Name - look for known stores after "Marina", "Ibn Batuta", etc.
    store_patterns = [
        r'(Marina Silverene)',
        r'(Ibn Batuta Mall)',
        r'(Khurais Road)',
        r'(City Center Deira)',
        r'(Mall of the Emirates)',
        r'CARREFOUR\s+([A-Za-z\s]+?)(?:\n|Po Box|TRN)',
    ]
    for pattern in store_patterns:
        store_match = re.search(pattern, pdf_text, re.IGNORECASE)
        if store_match:
            result["store_name"] = store_match.group(1).strip()
            break

    # =========================================================================
    # Extract Totals
    # =========================================================================

    # Total Amount Incl. VAT
    total_match = re.search(r'Total Amount Incl\.?\s*VAT\s*(?:AED)?\s*([\d,]+\.?\d*)', pdf_text, re.IGNORECASE)
    if total_match:
        result["total_incl_vat"] = float(total_match.group(1).replace(',', ''))
    else:
        # Try alternate pattern
        total_match2 = re.search(r'AED\s*([\d,]+\.?\d*)\s*$', pdf_text, re.MULTILINE)
        if total_match2:
            result["total_incl_vat"] = float(total_match2.group(1).replace(',', ''))
        else:
            result["parse_errors"].append("Could not extract total_incl_vat")

    # VAT Amount and Rate - look in the VAT summary table
    # Pattern: 5% | 153.33 | 7.67
    vat_summary_match = re.search(r'(\d+)%\s+([\d,]+\.?\d*)\s+([\d,]+\.?\d*)', pdf_text)
    if vat_summary_match:
        result["vat_rate"] = float(vat_summary_match.group(1))
        result["total_excl_vat"] = float(vat_summary_match.group(2).replace(',', ''))
        result["vat_amount"] = float(vat_summary_match.group(3).replace(',', ''))
    else:
        result["parse_errors"].append("Could not extract VAT summary")

    result["currency"] = "AED"

    # Payment Method
    payment_match = re.search(r'Payment Type\s*[:.]?\s*([A-Za-z\s]+?)(?:\n|Amount)', pdf_text)
    if payment_match:
        result["payment_method"] = payment_match.group(1).strip()

    # =========================================================================
    # Extract Savings
    # =========================================================================

    promo_match = re.search(r'Promo savings\s*[^\d]*([\d.]+)', pdf_text, re.IGNORECASE)
    if promo_match:
        result["savings"]["promo_savings"] = float(promo_match.group(1))

    product_match = re.search(r'Products? savings\s*[^\d]*([\d.]+)', pdf_text, re.IGNORECASE)
    if product_match:
        result["savings"]["product_savings"] = float(product_match.group(1))

    total_savings_match = re.search(r'Total savings\s*[^\d]*([\d.]+)', pdf_text, re.IGNORECASE)
    if total_savings_match:
        result["savings"]["total_savings"] = float(total_savings_match.group(1))

    # =========================================================================
    # Extract Line Items
    # =========================================================================

    result["line_items"] = parse_line_items(pdf_text)

    return result


def parse_line_items(pdf_text: str) -> List[Dict[str, Any]]:
    """
    Parse line items from Carrefour receipt.

    With pdftotext -layout, each item has:
    - Description + 9 numbers on the same line (or description spans multiple lines)
    - Arabic translation lines
    - Barcode: XXXXX line

    Numbers are: qty_ordered, qty_delivered, unit_price_incl, unit_price_excl, total_excl, vat_rate, vat_amt, discount, total_incl
    """
    items = []

    # Pattern to match a line ending with 9 numbers (the item data)
    # The numbers are at the end of the line, separated by whitespace
    item_line_pattern = re.compile(
        r'^(.+?)\s+'  # Description (non-greedy)
        r'(\d+\.?\d*)\s+'  # qty_ordered
        r'(\d+\.?\d*)\s+'  # qty_delivered
        r'(\d+\.?\d*)\s+'  # unit_price_incl_vat
        r'(\d+\.?\d*)\s+'  # unit_price_excl_vat
        r'(\d+\.?\d*)\s+'  # total_excl_vat
        r'(\d+\.?\d*)\s+'  # vat_rate
        r'(\d+\.?\d*)\s+'  # vat_amount
        r'(\d+\.?\d*)\s+'  # discount
        r'(\d+\.?\d*)\s*$'  # total_incl_vat
    )

    barcode_pattern = re.compile(r'Barcode:\s*(\d+)')

    lines = pdf_text.split('\n')
    current_item = None
    extra_description = []

    for line in lines:
        # Skip header/footer lines
        if any(skip in line for skip in [
            'Majid Al Futtaim', 'Tax Invoice', 'Order No', 'Invoice No',
            'CUSTOMER INFORMATION', 'STORE INFORMATION', 'Description',
            'Thank you for shopping', 'Total Amount', 'VAT %',
            'Payment Type', 'Promo savings', 'Products savings',
            'Total savings', 'Your Savings', 'Refund Note',
            'This sale was accepted', 'Page ', 'TRN ', 'City Center',
            'Ordered', 'Delivered', 'Unit Price', 'Substitution'
        ]):
            continue

        # Check if this line contains item data (description + 9 numbers)
        match = item_line_pattern.match(line)
        if match:
            # Save previous item if exists
            if current_item:
                items.append(current_item)

            description = match.group(1).strip()
            current_item = {
                "description": description,
                "barcode": None,
                "qty_ordered": float(match.group(2)),
                "qty_delivered": float(match.group(3)),
                "unit_price_incl_vat": float(match.group(4)),
                "unit_price_excl_vat": float(match.group(5)),
                "total_excl_vat": float(match.group(6)),
                "vat_rate": float(match.group(7)),
                "vat_amount": float(match.group(8)),
                "discount": float(match.group(9)),
                "total_incl_vat": float(match.group(10))
            }

            # Check for "(Free)" marker
            if current_item["total_incl_vat"] == 0:
                current_item["is_free"] = True

            extra_description = []
            continue

        # Check for barcode line
        barcode_match = barcode_pattern.search(line)
        if barcode_match and current_item:
            current_item["barcode"] = barcode_match.group(1)
            # Finalize description with any extra lines
            if extra_description:
                full_desc = current_item["description"] + " " + " ".join(extra_description)
                current_item["description"] = clean_description(full_desc)
            else:
                current_item["description"] = clean_description(current_item["description"])
            continue

        # Check for voucher discount line
        voucher_match = re.search(r'Voucher Discount:\s*([\d.]+)\s*AED', line, re.IGNORECASE)
        if voucher_match and current_item:
            current_item["voucher_discount"] = float(voucher_match.group(1))
            continue

        # If we have a current item and this line looks like additional description
        # (English text continuation, not Arabic, not empty)
        if current_item and line.strip():
            stripped = line.strip()
            # Skip Arabic-only lines
            if not is_arabic_only(stripped):
                # Skip lines that are just numbers or very short
                if len(stripped) > 3 and not re.match(r'^[\d\s.,]+$', stripped):
                    # Skip known non-description lines
                    if not stripped.startswith(('Po Box', 'Dubai', 'UAE', 'http', 'Customer Care')):
                        extra_description.append(stripped)

    # Don't forget the last item
    if current_item:
        if extra_description and not current_item.get("barcode"):
            full_desc = current_item["description"] + " " + " ".join(extra_description)
            current_item["description"] = clean_description(full_desc)
        items.append(current_item)

    return items


def clean_description(desc: str) -> str:
    """Clean up product description."""
    # Remove RTL/LTR embedding and formatting characters
    desc = re.sub(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]+', '', desc)
    # Remove Arabic script (main Arabic, Arabic Supplement, Arabic Extended)
    desc = re.sub(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]+', '', desc)
    # Remove extra whitespace
    desc = ' '.join(desc.split())
    # Remove trailing commas
    desc = desc.strip().rstrip(',')
    # Remove "(Free)" suffix if present - keep as separate field
    desc = re.sub(r'\s*\(Free\)\s*$', '', desc)
    return desc


def is_arabic_only(text: str) -> bool:
    """Check if text contains only Arabic characters and whitespace."""
    arabic_pattern = re.compile(r'^[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\s\d.]+$')
    return bool(arabic_pattern.match(text))


def validate_parsed_receipt(parsed: Dict[str, Any]) -> List[str]:
    """
    Validate parsed receipt data for completeness.

    Returns list of validation errors (empty if valid).
    """
    errors = []

    # Required fields
    if not parsed.get("invoice_no"):
        errors.append("Missing invoice_no")
    if not parsed.get("invoice_date"):
        errors.append("Missing invoice_date")
    if parsed.get("total_incl_vat") is None:
        errors.append("Missing total_incl_vat")
    if parsed.get("vat_amount") is None:
        errors.append("Missing vat_amount")

    # Cross-validate totals
    if parsed.get("total_incl_vat") and parsed.get("total_excl_vat") and parsed.get("vat_amount"):
        calculated_total = parsed["total_excl_vat"] + parsed["vat_amount"]
        if abs(calculated_total - parsed["total_incl_vat"]) > 0.02:  # Allow 2 fils tolerance
            errors.append(f"Total mismatch: {parsed['total_excl_vat']} + {parsed['vat_amount']} != {parsed['total_incl_vat']}")

    # Validate line items sum
    if parsed.get("line_items") and parsed.get("total_incl_vat"):
        items_total = sum(item.get("total_incl_vat", 0) for item in parsed["line_items"])
        # Note: voucher_discount is metadata only - item totals already reflect final prices
        if abs(items_total - parsed["total_incl_vat"]) > 0.10:  # Allow 10 fils tolerance for rounding
            errors.append(f"Line items sum ({items_total:.2f}) doesn't match total ({parsed['total_incl_vat']:.2f})")

    return errors


# For testing
if __name__ == "__main__":
    import sys
    import subprocess
    import json

    if len(sys.argv) < 2:
        print("Usage: python carrefour_parser.py <pdf_file>")
        sys.exit(1)

    pdf_path = sys.argv[1]

    # Extract text using pdftotext with layout preservation
    result = subprocess.run(['pdftotext', '-layout', pdf_path, '-'], capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error extracting text: {result.stderr}")
        sys.exit(1)

    pdf_text = result.stdout

    # Parse
    parsed = parse_carrefour_receipt(pdf_text)

    # Validate
    validation_errors = validate_parsed_receipt(parsed)
    if validation_errors:
        parsed["validation_errors"] = validation_errors

    # Output
    print(json.dumps(parsed, indent=2, ensure_ascii=False))
