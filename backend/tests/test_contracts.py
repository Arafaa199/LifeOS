#!/usr/bin/env python3
"""
Nexus API Contract Tests

Validates all API endpoints against their JSON Schema contracts.
Tests both successful responses and error handling.

Usage:
    python test_contracts.py              # Run all tests
    python test_contracts.py --dry-run    # Print what would be tested
    python test_contracts.py --verbose    # Show detailed validation errors

Environment Variables:
    NEXUS_BASE_URL - Base URL (default: https://n8n.rfanw/webhook/)
    NEXUS_API_KEY  - API key for X-API-Key header (required)
"""

import argparse
import json
import os
import sys
import uuid
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from pathlib import Path
from typing import Any

try:
    import requests
    import jsonschema
    from jsonschema import Draft202012Validator, ValidationError
except ImportError:
    print("Missing dependencies. Install with: pip install requests jsonschema")
    sys.exit(1)


# =============================================================================
# Configuration
# =============================================================================

BASE_URL = os.environ.get("NEXUS_BASE_URL", "https://n8n.rfanw/webhook/")
API_KEY = os.environ.get("NEXUS_API_KEY", "")
SCHEMAS_DIR = Path(__file__).parent.parent / "contracts" / "_schemas"
WORKFLOWS_DIR = Path(__file__).parent.parent / "n8n-workflows"
TIMEOUT = 30


class TestResult(Enum):
    PASS = "PASS"
    FAIL = "FAIL"
    SKIP = "SKIP"
    ERROR = "ERROR"


@dataclass
class TestCase:
    name: str
    method: str
    endpoint: str
    query_params: dict = field(default_factory=dict)
    body: dict | None = None
    response_schema: str | None = None
    request_schema: str | None = None
    expect_error: bool = False
    description: str = ""


@dataclass
class TestReport:
    name: str
    result: TestResult
    duration_ms: float = 0
    status_code: int = 0
    errors: list[str] = field(default_factory=list)
    response_preview: str = ""


# =============================================================================
# Schema Loading
# =============================================================================

def load_schema(schema_name: str) -> dict | None:
    """Load a JSON schema from the _schemas directory."""
    schema_path = SCHEMAS_DIR / schema_name
    if not schema_path.exists():
        return None
    try:
        with open(schema_path) as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        print(f"  ERROR: Invalid JSON in {schema_name}: {e}")
        return None


def load_all_schemas() -> dict[str, dict]:
    """Load all schemas from the _schemas directory."""
    schemas = {}
    if not SCHEMAS_DIR.exists():
        print(f"WARNING: Schemas directory not found: {SCHEMAS_DIR}")
        return schemas

    for schema_file in SCHEMAS_DIR.glob("*.json"):
        schema = load_schema(schema_file.name)
        if schema:
            schemas[schema_file.name] = schema
    return schemas


# =============================================================================
# Test Value Generation
# =============================================================================

def generate_test_value(prop_schema: dict, prop_name: str = "") -> Any:
    """Generate a sensible test value based on JSON Schema property definition."""
    prop_type = prop_schema.get("type", "string")

    # Handle nullable types
    if isinstance(prop_type, list):
        prop_type = [t for t in prop_type if t != "null"][0] if len(prop_type) > 1 else prop_type[0]

    # Check for enum first
    if "enum" in prop_schema:
        return prop_schema["enum"][0]

    # Check for const
    if "const" in prop_schema:
        return prop_schema["const"]

    # Generate by type
    if prop_type == "string":
        fmt = prop_schema.get("format", "")
        if fmt == "uuid":
            return str(uuid.uuid4())
        elif fmt == "date":
            return datetime.now().strftime("%Y-%m-%d")
        elif fmt == "date-time":
            return datetime.now().isoformat() + "Z"
        elif prop_name == "text":
            return "Test text 25 AED"
        elif prop_name == "label" or prop_name == "name" or prop_name == "title":
            return f"Test {prop_name}"
        else:
            return "test_value"

    elif prop_type == "integer":
        minimum = prop_schema.get("minimum", 1)
        maximum = prop_schema.get("maximum", 100)
        return max(minimum, min(50, maximum))

    elif prop_type == "number":
        minimum = prop_schema.get("minimum", 0)
        maximum = prop_schema.get("maximum", 100)
        return max(minimum, min(50.0, maximum))

    elif prop_type == "boolean":
        return True

    elif prop_type == "array":
        items_schema = prop_schema.get("items", {})
        return [generate_test_object(items_schema)]

    elif prop_type == "object":
        return generate_test_object(prop_schema)

    return None


def generate_test_object(schema: dict) -> dict:
    """Generate a minimal valid test object from a JSON Schema."""
    result = {}
    required = schema.get("required", [])
    properties = schema.get("properties", {})

    # Generate only required fields
    for prop_name in required:
        if prop_name in properties:
            result[prop_name] = generate_test_value(properties[prop_name], prop_name)

    return result


def generate_minimal_request(request_schema: dict) -> dict:
    """Generate a minimal valid request body from a request schema."""
    return generate_test_object(request_schema)


# =============================================================================
# Error Response Schema
# =============================================================================

ERROR_RESPONSE_SCHEMA = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "required": ["success"],
    "properties": {
        "success": {"type": "boolean", "const": False},
        "error": {
            "type": "object",
            "required": ["code", "message"],
            "properties": {
                "code": {"type": "string"},
                "message": {"type": "string"}
            }
        }
    }
}


# =============================================================================
# Test Case Definitions
# =============================================================================

def get_test_cases() -> list[TestCase]:
    """Define all test cases for endpoints."""
    today = datetime.now().strftime("%Y-%m-%d")
    yesterday = (datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d")
    next_month = (datetime.now() + timedelta(days=30)).strftime("%Y-%m-%d")

    return [
        # =====================================================================
        # GET Endpoints - Response Validation
        # =====================================================================

        # Dashboard
        TestCase(
            name="GET nexus-dashboard-today",
            method="GET",
            endpoint="nexus-dashboard-today",
            response_schema="nexus-dashboard-today.json",
            description="Fetch complete dashboard payload"
        ),
        TestCase(
            name="GET nexus-sleep",
            method="GET",
            endpoint="nexus-sleep",
            query_params={"date": today},
            response_schema="nexus-sleep.json",
            description="Fetch sleep data for today"
        ),
        TestCase(
            name="GET nexus-sleep-history",
            method="GET",
            endpoint="nexus-sleep-history",
            query_params={"days": "7"},
            response_schema="nexus-sleep-history.json",
            description="Fetch 7-day sleep history"
        ),
        TestCase(
            name="GET nexus-health-timeseries",
            method="GET",
            endpoint="nexus-health-timeseries",
            query_params={"days": "30"},
            response_schema="nexus-health-timeseries.json",
            description="Fetch 30-day health metrics"
        ),

        # Finance
        TestCase(
            name="GET nexus-finance-summary",
            method="GET",
            endpoint="nexus-finance-summary",
            response_schema="nexus-finance-summary.json",
            description="Fetch finance summary"
        ),
        TestCase(
            name="GET nexus-budgets",
            method="GET",
            endpoint="nexus-budgets",
            response_schema="nexus-budgets.json",
            description="Fetch current budgets"
        ),
        TestCase(
            name="GET nexus-categories",
            method="GET",
            endpoint="nexus-categories",
            response_schema="nexus-categories.json",
            description="Fetch expense categories"
        ),
        TestCase(
            name="GET nexus-recurring",
            method="GET",
            endpoint="nexus-recurring",
            response_schema="nexus-recurring.json",
            description="Fetch recurring items"
        ),
        TestCase(
            name="GET nexus-rules",
            method="GET",
            endpoint="nexus-rules",
            response_schema="nexus-rules.json",
            description="Fetch merchant rules"
        ),
        TestCase(
            name="GET nexus-monthly-trends",
            method="GET",
            endpoint="nexus-monthly-trends",
            response_schema="nexus-monthly-trends.json",
            description="Fetch monthly spending trends"
        ),

        # Nutrition
        TestCase(
            name="GET nexus-food-search",
            method="GET",
            endpoint="nexus-food-search",
            query_params={"q": "chicken", "limit": "5"},
            response_schema="nexus-food-search.json",
            description="Search food database"
        ),

        # Documents
        TestCase(
            name="GET nexus-documents",
            method="GET",
            endpoint="nexus-documents",
            response_schema="nexus-documents.json",
            description="Fetch all documents"
        ),
        TestCase(
            name="GET nexus-reminders",
            method="GET",
            endpoint="nexus-reminders",
            query_params={"start": yesterday, "end": next_month},
            response_schema="nexus-reminders.json",
            description="Fetch reminders in date range"
        ),

        # Notes
        TestCase(
            name="GET nexus-notes-search",
            method="GET",
            endpoint="nexus-notes-search",
            query_params={"q": "test", "limit": "10"},
            response_schema="nexus-notes-search.json",
            description="Search Obsidian notes"
        ),

        # Ops
        TestCase(
            name="GET ops-health",
            method="GET",
            endpoint="ops-health",
            response_schema="ops-health.json",
            description="Fetch system health status"
        ),

        # =====================================================================
        # POST Endpoints - Request + Response Validation
        # =====================================================================

        # Finance POST
        TestCase(
            name="POST nexus-expense",
            method="POST",
            endpoint="nexus-expense",
            request_schema="nexus-expense-request.json",
            description="Log quick expense"
        ),
        TestCase(
            name="POST nexus-transaction",
            method="POST",
            endpoint="nexus-transaction",
            request_schema="nexus-transaction-request.json",
            description="Log structured transaction"
        ),
        TestCase(
            name="POST nexus-income",
            method="POST",
            endpoint="nexus-income",
            request_schema="nexus-income-request.json",
            description="Log income"
        ),
        TestCase(
            name="POST nexus-budgets",
            method="POST",
            endpoint="nexus-budgets",
            request_schema="nexus-budgets-request.json",
            description="Create/update budget"
        ),
        TestCase(
            name="POST nexus-recurring",
            method="POST",
            endpoint="nexus-recurring",
            request_schema="nexus-recurring-request.json",
            description="Create recurring item"
        ),

        # Health POST
        TestCase(
            name="POST nexus-weight",
            method="POST",
            endpoint="nexus-weight",
            request_schema="nexus-weight-request.json",
            description="Log weight"
        ),
        TestCase(
            name="POST nexus-mood",
            method="POST",
            endpoint="nexus-mood",
            request_schema="nexus-mood-request.json",
            description="Log mood"
        ),
        TestCase(
            name="POST nexus-workout",
            method="POST",
            endpoint="nexus-workout",
            request_schema="nexus-workout-request.json",
            description="Log workout"
        ),
        TestCase(
            name="POST nexus-supplement",
            method="POST",
            endpoint="nexus-supplement",
            request_schema="nexus-supplement-request.json",
            description="Create/update supplement"
        ),
        TestCase(
            name="POST nexus-supplement-log",
            method="POST",
            endpoint="nexus-supplement-log",
            request_schema="nexus-supplement-log-request.json",
            description="Log supplement intake"
        ),

        # Nutrition POST
        TestCase(
            name="POST nexus-food-log",
            method="POST",
            endpoint="nexus-food-log",
            request_schema="nexus-food-log-request.json",
            description="Log food"
        ),
        TestCase(
            name="POST nexus-water",
            method="POST",
            endpoint="nexus-water",
            request_schema="nexus-water-request.json",
            description="Log water intake"
        ),

        # Document POST
        TestCase(
            name="POST nexus-document",
            method="POST",
            endpoint="nexus-document",
            request_schema="nexus-document-request.json",
            description="Create document"
        ),
        TestCase(
            name="POST nexus-reminder-create",
            method="POST",
            endpoint="nexus-reminder-create",
            request_schema="nexus-reminder-create-request.json",
            description="Create reminder"
        ),

        # Music POST
        TestCase(
            name="POST nexus-music-events",
            method="POST",
            endpoint="nexus-music-events",
            request_schema="nexus-music-events-request.json",
            description="Log music listening events"
        ),

        # =====================================================================
        # Error Response Tests
        # =====================================================================

        TestCase(
            name="POST nexus-expense (missing required)",
            method="POST",
            endpoint="nexus-expense",
            body={},  # Missing required fields
            expect_error=True,
            description="Test VALIDATION_ERROR on missing required fields"
        ),
        TestCase(
            name="POST nexus-update-transaction (invalid ID)",
            method="POST",
            endpoint="nexus-update-transaction",
            body={"id": 999999999},  # Non-existent ID
            expect_error=True,
            description="Test NOT_FOUND on invalid transaction ID"
        ),
        TestCase(
            name="DELETE nexus-document (invalid ID)",
            method="DELETE",
            endpoint="nexus-document",
            query_params={"id": "999999999"},
            expect_error=True,
            description="Test NOT_FOUND on invalid document ID"
        ),
        TestCase(
            name="POST nexus-supplement-log (invalid supplement_id)",
            method="POST",
            endpoint="nexus-supplement-log",
            body={"supplement_id": 999999999, "status": "taken"},
            expect_error=True,
            description="Test NOT_FOUND on invalid supplement ID"
        ),
    ]


# =============================================================================
# Schema Validation
# =============================================================================

def validate_response(response_data: dict, schema: dict, verbose: bool = False) -> list[str]:
    """Validate response data against a JSON Schema. Returns list of errors."""
    errors = []

    try:
        validator = Draft202012Validator(schema)
        validation_errors = list(validator.iter_errors(response_data))

        for error in validation_errors:
            path = " -> ".join(str(p) for p in error.absolute_path) or "(root)"
            if verbose:
                errors.append(f"  Path: {path}\n    Error: {error.message}")
            else:
                errors.append(f"{path}: {error.message[:100]}")

    except Exception as e:
        errors.append(f"Validation exception: {str(e)}")

    return errors


# =============================================================================
# HTTP Request Execution
# =============================================================================

def make_request(test: TestCase, dry_run: bool = False, verbose: bool = False) -> TestReport:
    """Execute a test case and return the report."""
    import time

    url = BASE_URL.rstrip("/") + "/" + test.endpoint
    headers = {"X-API-Key": API_KEY, "Content-Type": "application/json"}

    # Build request body if needed
    body = test.body
    if body is None and test.request_schema:
        schema = load_schema(test.request_schema)
        if schema:
            body = generate_minimal_request(schema)

    if dry_run:
        return TestReport(
            name=test.name,
            result=TestResult.SKIP,
            errors=[f"DRY RUN: Would {test.method} {url}"],
            response_preview=json.dumps(body, indent=2) if body else "(no body)"
        )

    start_time = time.time()

    try:
        if test.method == "GET":
            resp = requests.get(url, headers=headers, params=test.query_params, timeout=TIMEOUT)
        elif test.method == "POST":
            resp = requests.post(url, headers=headers, params=test.query_params, json=body, timeout=TIMEOUT)
        elif test.method == "DELETE":
            resp = requests.delete(url, headers=headers, params=test.query_params, timeout=TIMEOUT)
        elif test.method == "PUT":
            resp = requests.put(url, headers=headers, params=test.query_params, json=body, timeout=TIMEOUT)
        else:
            return TestReport(
                name=test.name,
                result=TestResult.ERROR,
                errors=[f"Unsupported method: {test.method}"]
            )

        duration_ms = (time.time() - start_time) * 1000

    except requests.exceptions.Timeout:
        return TestReport(
            name=test.name,
            result=TestResult.ERROR,
            errors=[f"Request timed out after {TIMEOUT}s"]
        )
    except requests.exceptions.RequestException as e:
        return TestReport(
            name=test.name,
            result=TestResult.ERROR,
            errors=[f"Request failed: {str(e)}"]
        )

    # Parse response
    try:
        response_data = resp.json()
    except json.JSONDecodeError:
        return TestReport(
            name=test.name,
            result=TestResult.ERROR,
            status_code=resp.status_code,
            duration_ms=duration_ms,
            errors=[f"Invalid JSON response: {resp.text[:200]}"]
        )

    errors = []
    response_preview = json.dumps(response_data, indent=2)[:500]

    # Validate based on test type
    if test.expect_error:
        # Expecting an error response
        if resp.status_code >= 400:
            # Validate error response shape
            schema_errors = validate_response(response_data, ERROR_RESPONSE_SCHEMA, verbose)
            if schema_errors:
                errors.extend([f"Error response schema mismatch:"] + schema_errors)
        else:
            errors.append(f"Expected error status (4xx/5xx), got {resp.status_code}")
    else:
        # Expecting success
        if resp.status_code >= 400:
            errors.append(f"Unexpected error: {resp.status_code} - {response_data.get('error', {}).get('message', 'Unknown')}")
        elif test.response_schema:
            # Validate response against schema
            schema = load_schema(test.response_schema)
            if schema:
                schema_errors = validate_response(response_data, schema, verbose)
                if schema_errors:
                    errors.extend(schema_errors)
            else:
                errors.append(f"Schema not found: {test.response_schema}")

    result = TestResult.PASS if not errors else TestResult.FAIL

    return TestReport(
        name=test.name,
        result=result,
        status_code=resp.status_code,
        duration_ms=duration_ms,
        errors=errors,
        response_preview=response_preview
    )


# =============================================================================
# Duplicate Webhook Detection
# =============================================================================

def check_duplicate_webhooks() -> list[str]:
    """
    Scan n8n workflow JSON files for duplicate webhook paths.
    Returns list of issues found.
    """
    issues = []
    webhook_paths: dict[str, list[str]] = defaultdict(list)  # path -> [workflow files]

    if not WORKFLOWS_DIR.exists():
        issues.append(f"Workflows directory not found: {WORKFLOWS_DIR}")
        return issues

    for workflow_file in WORKFLOWS_DIR.rglob("*.json"):
        try:
            with open(workflow_file) as f:
                workflow = json.load(f)
        except (json.JSONDecodeError, IOError) as e:
            continue

        # n8n workflow structure: nodes array with webhook nodes
        nodes = workflow.get("nodes", [])
        for node in nodes:
            node_type = node.get("type", "")

            # Check for webhook nodes
            if "webhook" in node_type.lower():
                parameters = node.get("parameters", {})
                path = parameters.get("path", "")

                if path:
                    # Normalize path
                    path = path.strip("/").lower()
                    rel_path = str(workflow_file.relative_to(WORKFLOWS_DIR))
                    webhook_paths[path].append(rel_path)

    # Find duplicates
    for path, files in sorted(webhook_paths.items()):
        if len(files) > 1:
            issues.append(f"Duplicate webhook path /{path}: {', '.join(files)}")

    return issues


# =============================================================================
# Main Execution
# =============================================================================

def print_summary_table(reports: list[TestReport], webhook_issues: list[str]):
    """Print a formatted summary table."""

    print("\n" + "=" * 80)
    print("TEST RESULTS SUMMARY")
    print("=" * 80)

    # Count results
    counts = {r: 0 for r in TestResult}
    for report in reports:
        counts[report.result] += 1

    print(f"\nTotal Tests: {len(reports)}")
    print(f"  PASS:  {counts[TestResult.PASS]}")
    print(f"  FAIL:  {counts[TestResult.FAIL]}")
    print(f"  SKIP:  {counts[TestResult.SKIP]}")
    print(f"  ERROR: {counts[TestResult.ERROR]}")

    # Detailed results table
    print("\n" + "-" * 80)
    print(f"{'Test Name':<50} {'Result':<8} {'Status':<6} {'Time':<10}")
    print("-" * 80)

    for report in reports:
        status = str(report.status_code) if report.status_code else "-"
        time_str = f"{report.duration_ms:.0f}ms" if report.duration_ms else "-"
        result_str = report.result.value

        # Color coding for terminal
        if report.result == TestResult.PASS:
            result_str = f"\033[92m{result_str}\033[0m"  # Green
        elif report.result == TestResult.FAIL:
            result_str = f"\033[91m{result_str}\033[0m"  # Red
        elif report.result == TestResult.ERROR:
            result_str = f"\033[93m{result_str}\033[0m"  # Yellow

        print(f"{report.name[:50]:<50} {result_str:<17} {status:<6} {time_str:<10}")

    # Show failures
    failed_reports = [r for r in reports if r.result in (TestResult.FAIL, TestResult.ERROR)]
    if failed_reports:
        print("\n" + "=" * 80)
        print("FAILURES AND ERRORS")
        print("=" * 80)

        for report in failed_reports:
            print(f"\n{report.name}:")
            for error in report.errors[:5]:  # Limit to 5 errors
                print(f"  - {error}")

    # Webhook duplicates
    if webhook_issues:
        print("\n" + "=" * 80)
        print("DUPLICATE WEBHOOK PATHS")
        print("=" * 80)
        for issue in webhook_issues:
            print(f"  - {issue}")
    else:
        print("\n[OK] No duplicate webhook paths found")

    # Final status
    print("\n" + "=" * 80)
    if counts[TestResult.FAIL] == 0 and counts[TestResult.ERROR] == 0 and not webhook_issues:
        print("\033[92mALL TESTS PASSED\033[0m")
    else:
        print(f"\033[91m{counts[TestResult.FAIL] + counts[TestResult.ERROR]} TESTS FAILED\033[0m")
    print("=" * 80)


def main():
    parser = argparse.ArgumentParser(
        description="Nexus API Contract Tests",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument("--dry-run", action="store_true",
                        help="Print what would be tested without making requests")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Show detailed validation errors")
    parser.add_argument("--endpoint", "-e", type=str,
                        help="Run tests for a specific endpoint only")
    parser.add_argument("--skip-webhooks", action="store_true",
                        help="Skip duplicate webhook detection")

    args = parser.parse_args()

    # Validate environment
    if not args.dry_run and not API_KEY:
        print("ERROR: NEXUS_API_KEY environment variable is required")
        print("Set it with: export NEXUS_API_KEY='your-api-key'")
        sys.exit(1)

    print("=" * 80)
    print("NEXUS API CONTRACT TESTS")
    print("=" * 80)
    print(f"Base URL: {BASE_URL}")
    print(f"Schemas:  {SCHEMAS_DIR}")
    print(f"Mode:     {'DRY RUN' if args.dry_run else 'LIVE'}")
    print(f"Verbose:  {args.verbose}")

    # Load schemas
    schemas = load_all_schemas()
    print(f"Loaded {len(schemas)} schemas")

    # Get test cases
    test_cases = get_test_cases()

    # Filter by endpoint if specified
    if args.endpoint:
        test_cases = [t for t in test_cases if args.endpoint.lower() in t.endpoint.lower()]
        print(f"Filtered to {len(test_cases)} tests matching '{args.endpoint}'")

    print(f"\nRunning {len(test_cases)} tests...\n")

    # Run tests
    reports = []
    for i, test in enumerate(test_cases, 1):
        print(f"[{i}/{len(test_cases)}] {test.name}...", end=" ", flush=True)
        report = make_request(test, dry_run=args.dry_run, verbose=args.verbose)
        reports.append(report)

        # Quick status indicator
        if report.result == TestResult.PASS:
            print("\033[92m✓\033[0m")
        elif report.result == TestResult.SKIP:
            print("\033[90m○\033[0m")
        elif report.result == TestResult.FAIL:
            print("\033[91m✗\033[0m")
        else:
            print("\033[93m!\033[0m")

    # Check for duplicate webhooks
    webhook_issues = []
    if not args.skip_webhooks:
        print("\nChecking for duplicate webhook paths...")
        webhook_issues = check_duplicate_webhooks()

    # Print summary
    print_summary_table(reports, webhook_issues)

    # Exit code
    failed = sum(1 for r in reports if r.result in (TestResult.FAIL, TestResult.ERROR))
    sys.exit(1 if failed or webhook_issues else 0)


if __name__ == "__main__":
    main()
