#!/usr/bin/env python3
"""
SMS Pattern Tester - Validates regex patterns against actual SMS database
Run: python3 test_sms_patterns.py ~/tmp/lifeos_sms/chat.db
"""

import sqlite3
import re
import sys
from datetime import datetime

# =============================================================================
# PATTERN DEFINITIONS (from sms_regex_patterns.yaml)
# =============================================================================

PATTERNS = {
    # EmiratesNBD patterns
    "enbd_salary": {
        "regex": r'تم ايداع الراتب\s+(?P<currency>AED|SAR|JOD|USD)\s+(?P<amount>[\d,]+\.?\d*)\s+في\s+حسابك',
        "intent": "income",
        "sender": "EmiratesNBD"
    },
    "enbd_debit_purchase": {
        "regex": r'تمت عملية شراء بقيمة\s+(?P<currency>AED|SAR|JOD|USD|EUR|GBP)\s+(?P<amount>[\d,]+\.?\d*)\s+لدى\s+(?P<merchant>[^,]+)\s*,\s*(?P<city>.+?)\s+باستخدام بطاقة خصم',
        "intent": "expense",
        "sender": "EmiratesNBD"
    },
    "enbd_credit_purchase": {
        "regex": r'تمت عملية شراء في\s+(?P<currency>AED|SAR|JOD|USD)\s+(?P<amount>[\d,]+\.?\d*)\s+(?P<merchant>[^,]+),\s*(?P<city>.+?)\s+على البطاقة',
        "intent": "expense",
        "sender": "EmiratesNBD"
    },
    "enbd_atm": {
        "regex": r'لقد قمت بسحب مبلغ\s+(?P<currency>AED|SAR|JOD|USD)\s+(?P<amount>[\d,]+\.?\d*)\s+مستخدما بطاقة الصراف الآلي',
        "intent": "expense",
        "sender": "EmiratesNBD"
    },
    "enbd_transfer": {
        "regex": r'تم خصم\s+(?P<currency>AED|SAR|JOD|USD)\s+(?P<amount>[\d,]+\.?\d*)\s+من حسابك.*لتحويل الأموال',
        "intent": "transfer",
        "sender": "EmiratesNBD"
    },
    "enbd_cc_payment": {
        "regex": r'تم خصم مبلغ\s+(?P<currency>AED|SAR|JOD|USD)\s+(?P<amount>[\d,]+\.?\d*)\s+من حسابك.*لتسديد مستحقات بطاقتك',
        "intent": "expense",
        "sender": "EmiratesNBD"
    },
    "enbd_refund": {
        "regex": r'لقد تم إعادة مبلغ عملية شراء بقيمة\s+(?P<currency>AED|SAR|JOD|USD)\s+(?P<amount>[\d,]+\.?\d*)',
        "intent": "refund",
        "sender": "EmiratesNBD"
    },
    "enbd_declined": {
        "regex": r'تم رفض معاملة بقيمة\s+(?P<amount>[\d,]+\.?\d*)(?P<currency>AED|SAR|JOD|USD)',
        "intent": "declined",
        "sender": "EmiratesNBD"
    },
    "enbd_fund_hold": {
        "regex": r'تمّ تقييد مبلغ\s+(?P<currency>AED|SAR|JOD|USD)\s+(?P<amount>[\d,]+\.?\d*)\s+في حسابك',
        "intent": "transfer",
        "sender": "EmiratesNBD"
    },

    # AlRajhiBank patterns
    "alrajhi_pos": {
        "regex": r'PoS\nBy:(?P<card>\d+);(?P<method>[^\n]+)\nAmount:(?P<currency>SAR|USD|EUR|GBP)\s*(?P<amount>[\d,]+\.?\d*)',
        "intent": "expense",
        "sender": "AlRajhiBank"
    },
    "alrajhi_pos_intl": {
        "regex": r'PoS International\nBy:(?P<card>\d+);(?P<method>[^\n]+)\nAmount:(?P<currency>SAR|USD|EUR|GBP)\s*(?P<amount>[\d,]+\.?\d*)',
        "intent": "expense",
        "sender": "AlRajhiBank"
    },
    "alrajhi_online": {
        "regex": r'Online Purchase\nBy:(?P<card>\d+);(?P<method>[^\n]+)\n(?:From:(?P<from>\d+)\n)?Amount:(?P<currency>SAR|USD|EUR|GBP)\s*(?P<amount>[\d,]+\.?\d*)',
        "intent": "expense",
        "sender": "AlRajhiBank"
    },
    "alrajhi_refund": {
        "regex": r'Refund PoS\nBy:(?P<card>\d+);(?P<method>[^\n]+)\nAmount:(?P<currency>SAR|USD|EUR|GBP)\s*(?P<amount>[\d,]+\.?\d*)',
        "intent": "refund",
        "sender": "AlRajhiBank"
    },
    "alrajhi_transfer_out": {
        "regex": r'Internal Transfer\nFrom:(?P<from>\d+)\nAmount:(?P<currency>SAR|USD)\s*(?P<amount>[\d,]+\.?\d*)\nTo:(?P<to>[^\n]+)',
        "intent": "transfer",
        "sender": "AlRajhiBank"
    },
    "alrajhi_transfer_in": {
        "regex": r'Local Transfer\nVia:(?P<via>\w+)\nAmount:(?P<currency>SAR|USD)\s*(?P<amount>[\d,]+\.?\d*)\nTo:(?P<to>\d+)\nFrom:(?P<from>[^\n]+)',
        "intent": "income",
        "sender": "AlRajhiBank"
    },
    "alrajhi_transfer_in_internal": {
        "regex": r'Internal Transfer\nAmount:(?P<currency>SAR|USD)\s*(?P<amount>[\d,]+\.?\d*)\nTo:(?P<to>\d+)\nFrom:(?P<from>[^\n]+)',
        "intent": "income",
        "sender": "AlRajhiBank"
    },
    "alrajhi_atm": {
        "regex": r'Withdrawal:ATM\nBy:(?P<card>\d+);(?P<method>[^\n]+)\nAmount:(?P<currency>SAR|USD)\s*(?P<amount>[\d,]+\.?\d*)',
        "intent": "expense",
        "sender": "AlRajhiBank"
    },

    # JKB patterns
    "jkb_pos": {
        "regex": r'You have an approved purchase trx on POS for (?P<currency>SAR|JOD|AED|BHD|EGP|USD|EUR|GBP)\s*(?P<amount>[\d,]+\.?\d*)\s+on your card',
        "intent": "expense",
        "sender": "JKB"
    },
    "jkb_atm": {
        "regex": r'You have an approved withdrawal trx for (?P<currency>SAR|JOD|AED|BHD|EGP|USD)\s*(?P<amount>[\d,]+\.?\d*)\s+on your card',
        "intent": "expense",
        "sender": "JKB"
    },
    "jkb_declined": {
        "regex": r'You have a declined trx on your card.*for\s+(?P<currency>SAR|JOD|AED|BHD|EGP|USD|EUR|GBP)\s*(?P<amount>[\d,]+\.?\d*)\s+due to insufficient',
        "intent": "declined",
        "sender": "JKB"
    },
    "jkb_fee": {
        "regex": r'تم قيد مبلغ\s+(?P<amount>[\d,]+\.?\d*)\s+(?P<currency>JOD|SAR|USD)\s+على حسابكم.*عمولة تدني',
        "intent": "expense",
        "sender": "JKB"
    },
    "jkb_fee_arabic": {
        "regex": r'تم قيد مبلغ\s+(?P<amount>[\d,]+\.?\d*)\s+(?P<currency>دينار أردني|ريال سعودي|درهم إماراتي)\s+على حسابكم.*عمولة تدني',
        "intent": "expense",
        "sender": "JKB"
    },
    "jkb_deposit": {
        "regex": r'تم ايداع\s+مبلغ\s+(?P<amount>[\d,]+\.?\d*)\s+في\s+حسابك',
        "intent": "income",
        "sender": "JKB"
    },
    "jkb_credit": {
        "regex": r'تم قيد\s+مبلغ\s+(?P<amount>[\d,]+\.?\d*)\s+على\s+حسابك',
        "intent": "income",
        "sender": "JKB"
    },
    "jkb_ecommerce": {
        "regex": r'You have an approved Ecommerce trx\s+for\s+(?P<currency>SAR|JOD|AED|BHD|EGP|USD|EUR|GBP)\s*(?P<amount>[\d,]+\.?\d*)\s+on your card',
        "intent": "expense",
        "sender": "JKB"
    },
    "jkb_reversal": {
        "regex": r'You have an approved reversal trx for (?P<currency>SAR|JOD|AED|BHD|EGP|USD|EUR|GBP)\s*(?P<amount>[\d,]+\.?\d*)\s+on your card',
        "intent": "refund",
        "sender": "JKB"
    },

    # CAREEM
    "careem_refund": {
        "regex": r'your order (?P<order>\d+) has been cancelled and (?P<currency>AED|SAR|JOD|USD)\s*(?P<amount>[\d,]+\.?\d*)\s+has been refunded',
        "intent": "refund",
        "sender": "CAREEM"
    },

    # Amazon
    "amazon_refund": {
        "regex": r'Refund Issued: Amount (?P<currency>SAR|AED|USD|EUR)\s*(?P<amount>[\d,]+\.?\d*)',
        "intent": "refund",
        "sender": "Amazon"
    },
}

# Exclude patterns
EXCLUDE_PATTERNS = [
    r'(OTP|verification code|رمز التحقق|رمز التوثيق|code is|One-Time Password)',
    r'(add.*to.*wallet|Apple Pay|card.*ready for contactless)',
    r'(يوجد لديك دفعة.*تتطلب موافقتك)',
    r'(كشف حساب مصغّر|statement.*due)',
    r'(offer|discount|عرض.*خصم|خصم\s*\d+|extr\.ly)',
    r'(تم.*تحديث إعدادات الحماية)',
    r'(has been approved with a credit limit)',
    r'(Order for .+ is (successfully placed|shipped))',
]


def parse_amount(amount_str):
    """Convert amount string to float"""
    return float(amount_str.replace(',', ''))


def test_patterns(db_path):
    """Test patterns against SMS database"""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Get all messages with senders
    cursor.execute("""
        SELECT
            m.ROWID,
            datetime(m.date/1000000000 + 978307200, 'unixepoch') AS sent_at,
            h.id AS sender,
            m.text
        FROM message m
        LEFT JOIN handle h ON m.handle_id = h.ROWID
        WHERE m.text IS NOT NULL
        ORDER BY m.date DESC
    """)

    messages = cursor.fetchall()
    conn.close()

    # Stats
    stats = {
        "total": len(messages),
        "matched": 0,
        "excluded": 0,
        "unmatched_financial": 0,
        "by_pattern": {},
        "by_intent": {"income": [], "expense": [], "transfer": [], "refund": [], "declined": []},
    }

    # Initialize pattern stats
    for name in PATTERNS:
        stats["by_pattern"][name] = {"count": 0, "samples": []}

    unmatched_financial = []

    for rowid, sent_at, sender, text in messages:
        if not text:
            continue

        # Check if should be excluded
        excluded = False
        for exc_pattern in EXCLUDE_PATTERNS:
            if re.search(exc_pattern, text, re.IGNORECASE):
                excluded = True
                stats["excluded"] += 1
                break

        if excluded:
            continue

        # Try to match patterns
        matched = False
        for name, pattern_info in PATTERNS.items():
            regex = pattern_info["regex"]
            intent = pattern_info["intent"]

            match = re.search(regex, text, re.MULTILINE | re.IGNORECASE)
            if match:
                matched = True
                stats["matched"] += 1
                stats["by_pattern"][name]["count"] += 1

                # Extract entities
                entities = match.groupdict()
                amount = parse_amount(entities.get("amount", "0"))
                currency = entities.get("currency", "AED")

                result = {
                    "rowid": rowid,
                    "sent_at": sent_at,
                    "sender": sender,
                    "pattern": name,
                    "amount": amount,
                    "currency": currency,
                    "entities": entities,
                    "text_preview": text[:100]
                }

                stats["by_intent"][intent].append(result)

                if len(stats["by_pattern"][name]["samples"]) < 3:
                    stats["by_pattern"][name]["samples"].append(result)

                break  # Stop at first match

        # Check for potential unmatched financial messages
        if not matched:
            if re.search(r'(AED|SAR|JOD|درهم|ريال|دينار|\d+\.\d{2})', text):
                if sender and sender.lower() in ['emiratesnbd', 'alrajhibank', 'jkb', 'careem', 'amazon']:
                    stats["unmatched_financial"] += 1
                    if len(unmatched_financial) < 20:
                        unmatched_financial.append({
                            "rowid": rowid,
                            "sent_at": sent_at,
                            "sender": sender,
                            "text": text[:200]
                        })

    return stats, unmatched_financial


def print_report(stats, unmatched):
    """Print test results"""
    print("=" * 70)
    print("SMS PATTERN TEST REPORT")
    print("=" * 70)

    print(f"\nTotal messages: {stats['total']}")
    print(f"Matched: {stats['matched']}")
    print(f"Excluded (OTP/promo): {stats['excluded']}")
    print(f"Unmatched (potential financial): {stats['unmatched_financial']}")

    print("\n" + "-" * 70)
    print("MATCHES BY PATTERN:")
    print("-" * 70)
    for name, data in sorted(stats["by_pattern"].items(), key=lambda x: -x[1]["count"]):
        if data["count"] > 0:
            print(f"  {name}: {data['count']}")

    print("\n" + "-" * 70)
    print("MATCHES BY INTENT:")
    print("-" * 70)
    for intent, items in stats["by_intent"].items():
        total_amount = sum(i["amount"] for i in items)
        currencies = set(i["currency"] for i in items)
        print(f"  {intent}: {len(items)} transactions")
        if items:
            for curr in currencies:
                curr_total = sum(i["amount"] for i in items if i["currency"] == curr)
                print(f"    - {curr}: {curr_total:,.2f}")

    print("\n" + "-" * 70)
    print("SAMPLE MATCHES:")
    print("-" * 70)
    for name, data in stats["by_pattern"].items():
        if data["samples"]:
            print(f"\n  [{name}]")
            for sample in data["samples"][:2]:
                print(f"    {sample['sent_at']} | {sample['currency']} {sample['amount']:,.2f}")
                print(f"    Entities: {sample['entities']}")

    if unmatched:
        print("\n" + "-" * 70)
        print("UNMATCHED FINANCIAL MESSAGES (need new patterns):")
        print("-" * 70)
        for msg in unmatched[:10]:
            print(f"\n  [{msg['sender']}] {msg['sent_at']}")
            print(f"  {msg['text'][:150]}...")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 test_sms_patterns.py <path_to_chat.db>")
        sys.exit(1)

    db_path = sys.argv[1]
    print(f"Testing patterns against: {db_path}")

    stats, unmatched = test_patterns(db_path)
    print_report(stats, unmatched)
