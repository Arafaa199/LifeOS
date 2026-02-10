#!/usr/bin/env python3
"""
Nexus API Contract Validation Script

Tests all endpoints documented in CONTRACTS.md against the live n8n webhooks.
Validates that each endpoint responds with expected structure.

Usage:
    export NEXUS_API_KEY="your-api-key"
    python test_contracts.py
"""

import os
import sys
import json
import uuid
from datetime import datetime, timedelta
from typing import Optional

import requests
from requests.exceptions import RequestException

# Configuration
BASE_URL = "https://n8n.rfanw/webhook/"
API_KEY = os.environ.get("NEXUS_API_KEY")

if not API_KEY:
    print("ERROR: NEXUS_API_KEY environment variable not set")
    sys.exit(1)

# Common headers
HEADERS = {
    "X-API-Key": API_KEY,
    "Content-Type": "application/json"
}

# Test results storage
results: list[dict] = []


def get_today() -> str:
    """Returns today's date in YYYY-MM-DD format."""
    return datetime.now().strftime("%Y-%m-%d")


def get_month() -> str:
    """Returns current month in YYYY-MM format."""
    return datetime.now().strftime("%Y-%m")


def generate_uuid() -> str:
    """Generates a UUID v4 for idempotency."""
    return str(uuid.uuid4())


def test_endpoint(
    domain: str,
    name: str,
    method: str,
    path: str,
    params: Optional[dict] = None,
    body: Optional[dict] = None,
    timeout: int = 30
) -> dict:
    """
    Tests a single API endpoint.

    Returns a result dict with status, pass/fail, and any error message.
    """
    url = f"{BASE_URL}{path}"
    result = {
        "domain": domain,
        "name": name,
        "method": method,
        "path": path,
        "status_code": None,
        "passed": False,
        "error": None,
        "response_preview": None
    }

    try:
        if method == "GET":
            response = requests.get(url, headers=HEADERS, params=params, timeout=timeout)
        elif method == "POST":
            response = requests.post(url, headers=HEADERS, json=body or {}, timeout=timeout)
        elif method == "PUT":
            response = requests.put(url, headers=HEADERS, params=params, json=body or {}, timeout=timeout)
        elif method == "DELETE":
            response = requests.delete(url, headers=HEADERS, params=params, timeout=timeout)
        else:
            result["error"] = f"Unsupported method: {method}"
            return result

        result["status_code"] = response.status_code

        # Try to parse JSON response
        try:
            data = response.json()
            result["response_preview"] = json.dumps(data)[:200]

            # Check for success field OR valid dashboard response (which may not have success field)
            if response.status_code == 200:
                # Dashboard endpoint returns meta/today_facts structure
                if "meta" in data and "today_facts" in data:
                    result["passed"] = True
                # Most endpoints return success field
                elif data.get("success") is True:
                    result["passed"] = True
                # Some endpoints return success: false with error
                elif data.get("success") is False:
                    result["error"] = data.get("error", "Unknown error")
                # Workouts endpoint returns workouts array directly
                elif "workouts" in data or "supplements" in data:
                    result["passed"] = True
                else:
                    result["error"] = "Response missing 'success' field"
            else:
                result["error"] = f"HTTP {response.status_code}"

        except json.JSONDecodeError:
            result["error"] = "Response is not valid JSON"
            result["response_preview"] = response.text[:200]

    except RequestException as e:
        result["error"] = str(e)

    return result


def run_tests():
    """Runs all contract tests grouped by domain."""

    print("\n" + "=" * 80)
    print("NEXUS API CONTRACT VALIDATION")
    print("=" * 80)
    print(f"Base URL: {BASE_URL}")
    print(f"Date: {datetime.now().isoformat()}")
    print("=" * 80 + "\n")

    # =========================================================================
    # DASHBOARD
    # =========================================================================
    print("Testing DASHBOARD endpoints...")

    results.append(test_endpoint(
        domain="Dashboard",
        name="nexus-dashboard-today",
        method="GET",
        path="nexus-dashboard-today"
    ))

    results.append(test_endpoint(
        domain="Dashboard",
        name="nexus-sleep",
        method="GET",
        path="nexus-sleep",
        params={"date": get_today()}
    ))

    results.append(test_endpoint(
        domain="Dashboard",
        name="nexus-sleep-history",
        method="GET",
        path="nexus-sleep-history",
        params={"days": 7}
    ))

    results.append(test_endpoint(
        domain="Dashboard",
        name="nexus-health-timeseries",
        method="GET",
        path="nexus-health-timeseries",
        params={"days": 7}
    ))

    results.append(test_endpoint(
        domain="Dashboard",
        name="nexus-sync-status",
        method="GET",
        path="nexus-sync-status"
    ))

    results.append(test_endpoint(
        domain="Dashboard",
        name="nexus-whoop-refresh",
        method="POST",
        path="nexus-whoop-refresh",
        body={}
    ))

    # =========================================================================
    # FINANCE
    # =========================================================================
    print("Testing FINANCE endpoints...")

    results.append(test_endpoint(
        domain="Finance",
        name="nexus-finance-summary",
        method="GET",
        path="nexus-finance-summary"
    ))

    results.append(test_endpoint(
        domain="Finance",
        name="nexus-transactions",
        method="GET",
        path="nexus-transactions",
        params={"offset": 0, "limit": 5}
    ))

    # Use a unique client_id for test expense (won't create duplicate)
    expense_client_id = generate_uuid()
    results.append(test_endpoint(
        domain="Finance",
        name="nexus-expense",
        method="POST",
        path="nexus-expense",
        body={
            "text": "API Test 0.01 AED",
            "client_id": expense_client_id
        }
    ))

    # Use a unique client_id for test transaction
    transaction_client_id = generate_uuid()
    results.append(test_endpoint(
        domain="Finance",
        name="nexus-transaction",
        method="POST",
        path="nexus-transaction",
        body={
            "merchant_name": "API Test",
            "amount": -0.01,
            "category": "Other",
            "notes": "Contract validation test",
            "date": get_today(),
            "client_id": transaction_client_id
        }
    ))

    # We skip nexus-update-transaction and nexus-delete-transaction
    # to avoid modifying real data - just test they respond
    results.append(test_endpoint(
        domain="Finance",
        name="nexus-update-transaction",
        method="POST",
        path="nexus-update-transaction",
        body={
            "id": 999999,  # Non-existent ID, should fail gracefully
            "merchant_name": "Test",
            "amount": -1.00,
            "category": "Other"
        }
    ))

    results.append(test_endpoint(
        domain="Finance",
        name="nexus-delete-transaction",
        method="DELETE",
        path="nexus-delete-transaction",
        params={"id": 999999}  # Non-existent ID
    ))

    # Income test
    income_client_id = generate_uuid()
    results.append(test_endpoint(
        domain="Finance",
        name="nexus-income",
        method="POST",
        path="nexus-income",
        body={
            "source": "API Test",
            "amount": 0.01,
            "category": "Other",
            "notes": "Contract validation test",
            "date": get_today(),
            "is_recurring": False,
            "client_id": income_client_id
        }
    ))

    results.append(test_endpoint(
        domain="Finance",
        name="nexus-budgets (GET)",
        method="GET",
        path="nexus-budgets"
    ))

    results.append(test_endpoint(
        domain="Finance",
        name="nexus-budgets (POST)",
        method="POST",
        path="nexus-budgets",
        body={
            "month": get_month(),
            "category": "Other",
            "budget_amount": 100,
            "category_id": 16,  # Other category
            "notes": "Contract validation test"
        }
    ))

    results.append(test_endpoint(
        domain="Finance",
        name="nexus-categories",
        method="GET",
        path="nexus-categories"
    ))

    results.append(test_endpoint(
        domain="Finance",
        name="nexus-recurring (GET)",
        method="GET",
        path="nexus-recurring"
    ))

    results.append(test_endpoint(
        domain="Finance",
        name="nexus-recurring (POST)",
        method="POST",
        path="nexus-recurring",
        body={
            "name": "API Test Recurring",
            "amount": 0.01,
            "currency": "AED",
            "type": "expense",
            "cadence": "monthly",
            "day_of_month": 1,
            "category_id": 16,
            "auto_create": False
        }
    ))

    results.append(test_endpoint(
        domain="Finance",
        name="nexus-rules",
        method="GET",
        path="nexus-rules"
    ))

    results.append(test_endpoint(
        domain="Finance",
        name="nexus-monthly-trends",
        method="GET",
        path="nexus-monthly-trends"
    ))

    results.append(test_endpoint(
        domain="Finance",
        name="nexus-financial-position",
        method="GET",
        path="nexus-financial-position"
    ))

    results.append(test_endpoint(
        domain="Finance",
        name="nexus-create-correction",
        method="POST",
        path="nexus-create-correction",
        body={
            "transaction_id": 999999,  # Non-existent
            "amount": -1.00,
            "category": "Other",
            "reason": "test",
            "notes": "Contract validation test",
            "created_by": "test_script"
        }
    ))

    results.append(test_endpoint(
        domain="Finance",
        name="nexus-trigger-import",
        method="POST",
        path="nexus-trigger-import",
        body={}
    ))

    results.append(test_endpoint(
        domain="Finance",
        name="nexus-refresh-summary",
        method="POST",
        path="nexus-refresh-summary",
        body={}
    ))

    # =========================================================================
    # HEALTH
    # =========================================================================
    print("Testing HEALTH endpoints...")

    results.append(test_endpoint(
        domain="Health",
        name="nexus-weight",
        method="POST",
        path="nexus-weight",
        body={"weight_kg": 75.5}
    ))

    results.append(test_endpoint(
        domain="Health",
        name="nexus-mood",
        method="POST",
        path="nexus-mood",
        body={
            "mood": 7,
            "energy": 7,
            "notes": "Contract validation test"
        }
    ))

    results.append(test_endpoint(
        domain="Health",
        name="nexus-universal",
        method="POST",
        path="nexus-universal",
        body={
            "text": "Test log",
            "source": "test",
            "context": "auto"
        }
    ))

    results.append(test_endpoint(
        domain="Health",
        name="nexus-workouts (GET)",
        method="GET",
        path="nexus-workouts"
    ))

    results.append(test_endpoint(
        domain="Health",
        name="nexus-workout (POST)",
        method="POST",
        path="nexus-workout",
        body={
            "date": get_today(),
            "workout_type": "test",
            "name": "API Test Workout",
            "duration_min": 1,
            "calories_burned": 10,
            "avg_hr": 100,
            "max_hr": 120,
            "source": "test",
            "external_id": f"test-{generate_uuid()}"
        }
    ))

    # =========================================================================
    # NUTRITION
    # =========================================================================
    print("Testing NUTRITION endpoints...")

    results.append(test_endpoint(
        domain="Nutrition",
        name="nexus-food-log",
        method="POST",
        path="nexus-food-log",
        body={
            "text": "API test food 10 calories",
            "source": "test",
            "food_id": None,
            "meal_type": "snack"
        }
    ))

    results.append(test_endpoint(
        domain="Nutrition",
        name="nexus-food-search",
        method="GET",
        path="nexus-food-search",
        params={"q": "chicken", "limit": 5}
    ))

    results.append(test_endpoint(
        domain="Nutrition",
        name="nexus-nutrition-history",
        method="GET",
        path="nexus-nutrition-history",
        params={"date": get_today()}
    ))

    results.append(test_endpoint(
        domain="Nutrition",
        name="nexus-water",
        method="POST",
        path="nexus-water",
        body={"amount_ml": 250}
    ))

    results.append(test_endpoint(
        domain="Nutrition",
        name="nexus-fast-start",
        method="POST",
        path="nexus-fast-start",
        body={}
    ))

    results.append(test_endpoint(
        domain="Nutrition",
        name="nexus-fast-break",
        method="POST",
        path="nexus-fast-break",
        body={}
    ))

    results.append(test_endpoint(
        domain="Nutrition",
        name="nexus-fast-status",
        method="GET",
        path="nexus-fast-status"
    ))

    results.append(test_endpoint(
        domain="Nutrition",
        name="nexus-pending-meals",
        method="GET",
        path="nexus-pending-meals"
    ))

    results.append(test_endpoint(
        domain="Nutrition",
        name="nexus-meal-confirmation",
        method="POST",
        path="nexus-meal-confirmation",
        body={
            "meal_id": 999999,  # Non-existent
            "confirmed": True,
            "adjusted_calories": 500
        }
    ))

    # =========================================================================
    # DOCUMENTS
    # =========================================================================
    print("Testing DOCUMENTS endpoints...")

    results.append(test_endpoint(
        domain="Documents",
        name="nexus-documents",
        method="GET",
        path="nexus-documents"
    ))

    # Create a test document with unique client_id
    doc_client_id = generate_uuid()
    results.append(test_endpoint(
        domain="Documents",
        name="nexus-document (POST)",
        method="POST",
        path="nexus-document",
        body={
            "client_id": doc_client_id,
            "doc_type": "other",
            "label": "API Test Document",
            "issuer": "Test",
            "doc_number": "TEST123",
            "issue_date": get_today(),
            "expiry_date": (datetime.now() + timedelta(days=365)).strftime("%Y-%m-%d"),
            "reminders_enabled": False
        }
    ))

    results.append(test_endpoint(
        domain="Documents",
        name="nexus-document-update",
        method="POST",
        path="nexus-document-update",
        body={
            "id": 999999,  # Non-existent
            "label": "Updated Label",
            "notes": "Contract validation test"
        }
    ))

    results.append(test_endpoint(
        domain="Documents",
        name="nexus-document (DELETE)",
        method="DELETE",
        path="nexus-document",
        params={"id": 999999}  # Non-existent
    ))

    results.append(test_endpoint(
        domain="Documents",
        name="nexus-document-renew",
        method="POST",
        path="nexus-document-renew",
        body={
            "id": 999999,  # Non-existent
            "new_expiry_date": (datetime.now() + timedelta(days=730)).strftime("%Y-%m-%d"),
            "new_doc_number": "TEST456",
            "notes": "Contract validation test"
        }
    ))

    results.append(test_endpoint(
        domain="Documents",
        name="nexus-document-recreate-reminders",
        method="POST",
        path="nexus-document-recreate-reminders",
        body={"id": 999999}  # Non-existent
    ))

    # =========================================================================
    # REMINDERS
    # =========================================================================
    print("Testing REMINDERS endpoints...")

    # Get reminders for next 30 days
    start_date = datetime.now().strftime("%Y-%m-%d")
    end_date = (datetime.now() + timedelta(days=30)).strftime("%Y-%m-%d")

    results.append(test_endpoint(
        domain="Reminders",
        name="nexus-reminders",
        method="GET",
        path="nexus-reminders",
        params={"start": start_date, "end": end_date}
    ))

    results.append(test_endpoint(
        domain="Reminders",
        name="nexus-reminder-create",
        method="POST",
        path="nexus-reminder-create",
        body={
            "title": "API Test Reminder",
            "notes": "Contract validation test",
            "due_date": (datetime.now() + timedelta(days=7)).strftime("%Y-%m-%d"),
            "priority": 0,
            "list_name": "Reminders"
        }
    ))

    results.append(test_endpoint(
        domain="Reminders",
        name="nexus-reminder-update",
        method="POST",
        path="nexus-reminder-update",
        body={
            "id": 999999,  # Non-existent
            "reminder_id": "test-uuid",
            "title": "Updated Title",
            "is_completed": False
        }
    ))

    results.append(test_endpoint(
        domain="Reminders",
        name="nexus-reminder-delete",
        method="POST",
        path="nexus-reminder-delete",
        body={
            "id": 999999,  # Non-existent
            "reminder_id": "test-uuid"
        }
    ))

    # =========================================================================
    # NOTES
    # =========================================================================
    print("Testing NOTES endpoints...")

    results.append(test_endpoint(
        domain="Notes",
        name="nexus-notes-search",
        method="GET",
        path="nexus-notes-search",
        params={"q": "test", "limit": 5}
    ))

    results.append(test_endpoint(
        domain="Notes",
        name="nexus-note-update",
        method="PUT",
        path="nexus-note-update",
        params={"id": 999999},  # Non-existent
        body={
            "title": "Updated Title",
            "tags": ["test"]
        }
    ))

    results.append(test_endpoint(
        domain="Notes",
        name="nexus-note-delete",
        method="DELETE",
        path="nexus-note-delete",
        params={"id": 999999}  # Non-existent
    ))

    # =========================================================================
    # MUSIC
    # =========================================================================
    print("Testing MUSIC endpoints...")

    results.append(test_endpoint(
        domain="Music",
        name="nexus-music-events",
        method="POST",
        path="nexus-music-events",
        body={
            "events": [
                {
                    "session_id": generate_uuid(),
                    "track_title": "Test Track",
                    "artist": "Test Artist",
                    "album": "Test Album",
                    "duration_sec": 180,
                    "apple_music_id": "test-123",
                    "started_at": datetime.now().isoformat() + "Z",
                    "ended_at": (datetime.now() + timedelta(minutes=3)).isoformat() + "Z",
                    "source": "test"
                }
            ]
        }
    ))

    results.append(test_endpoint(
        domain="Music",
        name="nexus-music-history",
        method="GET",
        path="nexus-music-history",
        params={"limit": 5}
    ))

    # =========================================================================
    # HOME AUTOMATION
    # =========================================================================
    print("Testing HOME AUTOMATION endpoints...")

    results.append(test_endpoint(
        domain="Home",
        name="nexus-home-status",
        method="GET",
        path="nexus-home-status"
    ))

    results.append(test_endpoint(
        domain="Home",
        name="nexus-home-control",
        method="POST",
        path="nexus-home-control",
        body={
            "action": "turn_off",  # Safe action
            "entity_id": "light.nonexistent_test_light",  # Non-existent entity
            "data": {}
        }
    ))

    # =========================================================================
    # RECEIPTS
    # =========================================================================
    print("Testing RECEIPTS endpoints...")

    results.append(test_endpoint(
        domain="Receipts",
        name="nexus-receipts",
        method="GET",
        path="nexus-receipts"
    ))

    results.append(test_endpoint(
        domain="Receipts",
        name="nexus-receipt-detail",
        method="GET",
        path="nexus-receipt-detail",
        params={"id": 1}  # First receipt if exists
    ))

    results.append(test_endpoint(
        domain="Receipts",
        name="nexus-receipt-item-match",
        method="POST",
        path="nexus-receipt-item-match",
        body={
            "item_id": 999999,  # Non-existent
            "food_id": 1,
            "is_user_confirmed": True
        }
    ))

    results.append(test_endpoint(
        domain="Receipts",
        name="nexus-receipt-nutrition",
        method="GET",
        path="nexus-receipt-nutrition",
        params={"id": 1}  # First receipt if exists
    ))

    # =========================================================================
    # SUPPLEMENTS
    # =========================================================================
    print("Testing SUPPLEMENTS endpoints...")

    results.append(test_endpoint(
        domain="Supplements",
        name="nexus-supplements",
        method="GET",
        path="nexus-supplements"
    ))

    results.append(test_endpoint(
        domain="Supplements",
        name="nexus-supplement-log",
        method="POST",
        path="nexus-supplement-log",
        body={
            "supplement_id": 999999,  # Non-existent
            "status": "taken",
            "time_slot": "morning",
            "notes": None
        }
    ))

    results.append(test_endpoint(
        domain="Supplements",
        name="nexus-supplement",
        method="POST",
        path="nexus-supplement",
        body={
            "name": "API Test Supplement",
            "brand": "Test Brand",
            "dose_amount": 100,
            "dose_unit": "mg",
            "frequency": "daily",
            "times_of_day": ["morning"],
            "category": "test",
            "notes": "Contract validation test"
        }
    ))


def print_results():
    """Prints the test results summary table."""

    print("\n" + "=" * 120)
    print("TEST RESULTS SUMMARY")
    print("=" * 120)

    # Group by domain
    domains = {}
    for r in results:
        domain = r["domain"]
        if domain not in domains:
            domains[domain] = []
        domains[domain].append(r)

    passed_count = 0
    failed_count = 0

    for domain, tests in domains.items():
        print(f"\n{domain}")
        print("-" * 120)
        print(f"{'Endpoint':<40} {'Method':<8} {'Status':<8} {'Result':<8} {'Error'}")
        print("-" * 120)

        for t in tests:
            status = str(t["status_code"]) if t["status_code"] else "N/A"
            result = "PASS" if t["passed"] else "FAIL"
            error = t["error"][:60] if t["error"] else ""

            if t["passed"]:
                passed_count += 1
            else:
                failed_count += 1

            print(f"{t['name']:<40} {t['method']:<8} {status:<8} {result:<8} {error}")

    print("\n" + "=" * 120)
    print(f"TOTAL: {len(results)} tests | PASSED: {passed_count} | FAILED: {failed_count}")
    print("=" * 120)

    # Exit with error code if any tests failed
    if failed_count > 0:
        print(f"\n{failed_count} test(s) failed!")
        return 1
    else:
        print("\nAll tests passed!")
        return 0


def main():
    """Main entry point."""
    run_tests()
    exit_code = print_results()
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
