"""
Careem Quik Email Receipt Parser v1

Extracts structured data from Careem Quik delivery confirmation emails.
Parses the HTML email body (quoted-printable encoded) to extract line items and totals.

Output format:
{
    "vendor": "careem_quik",
    "order_date": "2026-01-25",
    "total_incl_vat": 143.80,
    "vat_amount": 6.71,
    "currency": "AED",
    "line_items": [
        {
            "description": "Nestle Lion Wild Cereal 410 g",
            "qty": 1,
            "unit_price": 25.45,
            "total": 25.45
        },
        ...
    ],
    "savings": {
        "discount": 6.95,
        "promo": 15.55,
        "total_savings": 22.50
    },
    "delivery": {
        "delivery_charge": 6.00,
        "delivery_fee": 3.95,
        "small_order_fee": 3.00,
        "free_delivery_discount": -6.00
    }
}
"""

import re
import hashlib
import quopri
from datetime import datetime
from typing import Dict, List, Optional, Any
from pathlib import Path
from email import policy
from email.parser import BytesParser

# Parser version - increment when parsing logic changes
PARSE_VERSION = 'careem_v1'


def decode_quoted_printable(text: str) -> str:
    """Decode quoted-printable encoded text."""
    try:
        # Handle =XX hex encoding
        return quopri.decodestring(text.encode('utf-8')).decode('utf-8')
    except:
        return text


def extract_html_from_eml(eml_path: str) -> str:
    """Extract HTML body from .eml file."""
    with open(eml_path, 'rb') as f:
        msg = BytesParser(policy=policy.default).parse(f)

    # Get HTML body
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_type() == 'text/html':
                return part.get_content()
    else:
        if msg.get_content_type() == 'text/html':
            return msg.get_content()

    return ""


def extract_email_date(eml_path: str) -> Optional[str]:
    """Extract date from email headers."""
    with open(eml_path, 'rb') as f:
        msg = BytesParser(policy=policy.default).parse(f)

    date_str = msg.get('Date', '')
    if date_str:
        try:
            # Parse RFC 2822 date format
            from email.utils import parsedate_to_datetime
            dt = parsedate_to_datetime(date_str)
            return dt.strftime('%Y-%m-%d')
        except:
            pass
    return None


def parse_careem_html(html_content: str) -> Dict[str, Any]:
    """
    Parse Careem Quik email HTML content.

    The HTML structure uses quoted-printable encoding with patterns like:
    - Items: <span style="color: #18AB33">QTY &times;</span> Item Name
    - Prices: AED XX.XX
    """
    result = {
        "parser_version": "1.0.0",
        "parse_version": PARSE_VERSION,
        "vendor": "careem_quik",
        "currency": "AED",
        "parse_errors": [],
        "line_items": [],
        "savings": {},
        "delivery": {}
    }

    # Decode quoted-printable if needed
    if '=3D' in html_content or '=\n' in html_content:
        html_content = decode_quoted_printable(html_content)

    # Remove soft line breaks from quoted-printable
    html_content = re.sub(r'=\n', '', html_content)

    # =========================================================================
    # Extract Line Items
    # =========================================================================
    # Pattern: <span style="color: #18AB33">QTY &times;</span> Item Name
    # Followed by: AED XX.XX (or <s>AED XX.XX</s> for original price and AED XX.XX for sale price)

    item_pattern = re.compile(
        r'<span[^>]*color:\s*#18AB33[^>]*>(\d+)\s*(?:×|&times;|x)\s*</span>\s*([^<]+)',
        re.IGNORECASE | re.DOTALL
    )

    # Find all items
    items_found = item_pattern.findall(html_content)

    # Find all AED amounts in order
    # Look for the pattern after each item
    price_pattern = re.compile(r'AED\s*([\d,]+\.?\d*)')
    strikethrough_pattern = re.compile(r'<s>AED\s*([\d,]+\.?\d*)</s>')

    # Get positions of items and their following prices
    for match in item_pattern.finditer(html_content):
        qty = int(match.group(1))
        description = match.group(2).strip()

        # Clean description - handle UTF-8 encoding issues and line continuations
        description = re.sub(r'\s*=C3=97\s*', ' × ', description)  # Handle × encoding
        description = re.sub(r'\s+', ' ', description)  # Normalize whitespace
        description = description.strip()

        # Find the price after this item (within next ~1500 chars - price is in adjacent table column)
        search_start = match.end()
        search_end = min(search_start + 1500, len(html_content))
        price_section = html_content[search_start:search_end]

        # Check for sale price (has strikethrough original)
        strike_match = strikethrough_pattern.search(price_section)
        if strike_match:
            # Find the sale price after the strikethrough
            after_strike = price_section[strike_match.end():]
            sale_match = price_pattern.search(after_strike)
            if sale_match:
                price = float(sale_match.group(1).replace(',', ''))
            else:
                price = 0.0
            original_price = float(strike_match.group(1).replace(',', ''))
        else:
            # Regular price
            price_match = price_pattern.search(price_section)
            if price_match:
                price = float(price_match.group(1).replace(',', ''))
            else:
                price = 0.0
            original_price = None

        item = {
            "description": description,
            "qty": qty,
            "unit_price": round(price / qty, 2) if qty > 0 else price,
            "total": price
        }
        if original_price and original_price != price:
            item["original_price"] = original_price
            item["discount"] = round(original_price - price, 2)

        result["line_items"].append(item)

    # =========================================================================
    # Extract Totals and Fees
    # =========================================================================
    # Note: Labels and values are in separate table columns - need to find label
    # then search ahead for the AED amount

    def find_amount_after_label(label: str, is_negative: bool = False) -> Optional[float]:
        """Find the AED amount that follows a label in the HTML."""
        idx = html_content.lower().find(label.lower())
        if idx < 0:
            return None
        # Search up to 3000 chars ahead for AED amount (table columns can be far apart in HTML)
        section = html_content[idx:idx + 3000]
        if is_negative:
            # For negative amounts like discounts, look for "- AED"
            match = re.search(r'-\s*AED\s*([\d,]+\.?\d*)', section)
        else:
            match = re.search(r'AED\s*([\d,]+\.?\d*)', section)
        if match:
            return float(match.group(1).replace(',', ''))
        return None

    # Total bill (main header)
    total_match = re.search(r'Your total bill:\s*AED\s*([\d,]+\.?\d*)', html_content)
    if total_match:
        result["total_incl_vat"] = float(total_match.group(1).replace(',', ''))

    # Order ID
    order_id_match = re.search(r'Order ID[:\s]*(\d+)', html_content)
    if order_id_match:
        result["order_id"] = order_id_match.group(1)

    # Original basket
    basket_val = find_amount_after_label('Original basket')
    if basket_val:
        result["original_basket"] = basket_val

    # Discount (negative)
    # Find "Discount" but not "Free delivery" or "Promo"
    discount_idx = html_content.find('Discount')
    if discount_idx > 0:
        discount_section = html_content[discount_idx:discount_idx + 1500]
        discount_match = re.search(r'-\s*AED\s*([\d,]+\.?\d*)', discount_section)
        if discount_match:
            result["savings"]["discount"] = float(discount_match.group(1).replace(',', ''))

    # Careem Plus Discount (negative) - may be labeled as "Careem Plus Discount" or "Promo"
    plus_discount_val = find_amount_after_label('Careem Plus Discount', is_negative=True)
    if plus_discount_val:
        result["savings"]["careem_plus_discount"] = plus_discount_val
    else:
        promo_val = find_amount_after_label('Promo', is_negative=True)
        if promo_val:
            result["savings"]["promo"] = promo_val

    # Subtotal after discount (may be labeled "Basket total" or "Subtotal after discount")
    subtotal_val = find_amount_after_label('Basket total')
    if subtotal_val:
        result["subtotal_after_discount"] = subtotal_val
    else:
        subtotal_val = find_amount_after_label('Subtotal after discount')
        if subtotal_val:
            result["subtotal_after_discount"] = subtotal_val

    # Delivery charge
    delivery_val = find_amount_after_label('Delivery charge')
    if delivery_val:
        result["delivery"]["delivery_charge"] = delivery_val

    # Delivery fee
    fee_val = find_amount_after_label('Delivery fee')
    if fee_val:
        result["delivery"]["delivery_fee"] = fee_val

    # Small order fee
    small_order_val = find_amount_after_label('Small order fee')
    if small_order_val:
        result["delivery"]["small_order_fee"] = small_order_val

    # Free delivery discount (negative)
    free_del_val = find_amount_after_label('Free delivery', is_negative=True)
    if free_del_val:
        result["delivery"]["free_delivery_discount"] = free_del_val

    # Service fee
    service_fee_val = find_amount_after_label('Service fee')
    if service_fee_val:
        result["delivery"]["service_fee"] = service_fee_val

    # Captain reward
    captain_val = find_amount_after_label('Captain reward')
    if captain_val:
        result["delivery"]["captain_reward"] = captain_val

    # VAT
    vat_val = find_amount_after_label('5% VAT')
    if vat_val:
        result["vat_amount"] = vat_val
        result["vat_rate"] = 5.0

    # Payment method (Apple Pay, Card, etc.) - search near end of email
    payment_methods = ['Apple Pay', 'Google Pay', 'Visa', 'Mastercard', 'Cash', 'Card']
    for pm in payment_methods:
        if pm.lower() in html_content.lower():
            result["payment_method"] = pm
            break

    # Total savings message ("You have saved AED X.XX on this order")
    # The AED amount may be in a span element, so search more broadly
    saved_match = re.search(r'You have saved.*?AED\s*([\d,]+\.?\d*)', html_content, re.IGNORECASE | re.DOTALL)
    if saved_match:
        result["savings"]["advertised_savings"] = float(saved_match.group(1).replace(',', ''))

    # Compute total savings
    total_savings = (
        result["savings"].get("discount", 0) +
        result["savings"].get("promo", 0) +
        result["savings"].get("careem_plus_discount", 0)
    )
    if total_savings > 0:
        result["savings"]["total_savings"] = round(total_savings, 2)

    return result


def parse_careem_receipt(eml_path: str) -> Dict[str, Any]:
    """
    Parse Careem Quik receipt from .eml file.

    Args:
        eml_path: Path to .eml file

    Returns:
        Dictionary with parsed receipt data
    """
    html_content = extract_html_from_eml(eml_path)
    if not html_content:
        return {
            "parse_errors": ["Could not extract HTML content from email"],
            "vendor": "careem_quik"
        }

    result = parse_careem_html(html_content)

    # Add order date from email headers
    order_date = extract_email_date(eml_path)
    if order_date:
        result["order_date"] = order_date

    # Compute content hash for deduplication
    content_hash = hashlib.sha256(html_content.encode('utf-8')).hexdigest()
    result["content_hash"] = content_hash

    return result


def validate_parsed_receipt(parsed: Dict[str, Any]) -> List[str]:
    """
    Validate parsed receipt data.

    Returns list of validation errors (empty if valid).
    """
    errors = []

    if not parsed.get("line_items"):
        errors.append("No line items found")

    if parsed.get("total_incl_vat") is None:
        errors.append("Missing total")

    # Cross-validate: sum of items should be close to subtotal_after_discount
    # (items show post-discount prices, not original prices)
    if parsed.get("line_items"):
        items_sum = sum(item.get("total", 0) for item in parsed["line_items"])
        subtotal = parsed.get("subtotal_after_discount")
        if subtotal and abs(items_sum - subtotal) > 1.0:  # Allow 1 AED tolerance
            errors.append(f"Items sum ({items_sum:.2f}) differs from subtotal ({subtotal:.2f})")

    return errors


# For testing
if __name__ == "__main__":
    import sys
    import json

    if len(sys.argv) < 2:
        print("Usage: python careem_parser.py <eml_file>")
        sys.exit(1)

    eml_path = sys.argv[1]

    # Parse
    parsed = parse_careem_receipt(eml_path)

    # Validate
    validation_errors = validate_parsed_receipt(parsed)
    if validation_errors:
        parsed["validation_errors"] = validation_errors

    # Output
    print(json.dumps(parsed, indent=2, ensure_ascii=False))
