#!/usr/bin/env python3
"""
Patch all n8n webhook workflows to:
1. Reference the global error handler workflow
2. Add standardized error response nodes to POST webhooks

Usage:
  python3 patch-webhook-error-handling.py <error_handler_workflow_id>

The error_handler_workflow_id is assigned by n8n when you import
error-handler-global.json. Find it via:
  n8n CLI: n8n list:workflow
  n8n API: GET /api/v1/workflows?search=Global+Error+Handler

Example:
  python3 patch-webhook-error-handling.py w8KjL2mN3pQ4rS5t
"""

import json
import glob
import sys
import os
from pathlib import Path

WORKFLOWS_DIR = Path(__file__).parent.parent / "n8n-workflows"

# Postgres credential ID used across the project
POSTGRES_CRED_ID = "p5cyLWCZ9Db6GiiQ"
POSTGRES_CRED_NAME = "Nexus PostgreSQL"

# Nodes to skip (don't add error handling to infrastructure workflows)
SKIP_WORKFLOWS = {
    "error-handler-global.json",
    "dlq-retry-processor.json",
    "refresh-queue-worker.json",
}


def make_error_response_node(position_x, position_y):
    """Create a standardized error response node."""
    return {
        "parameters": {
            "respondWith": "json",
            "responseBody": '={\n  "success": false,\n  "error": "Internal processing error",\n  "code": "PROCESSING_ERROR",\n  "timestamp": "{{ $now.toISO() }}"\n}',
            "options": {"responseCode": 500}
        },
        "id": "error-response-std",
        "name": "Error Response (Standard)",
        "type": "n8n-nodes-base.respondToWebhook",
        "position": [position_x, position_y],
        "typeVersion": 1.1
    }


def patch_workflow(filepath, error_workflow_id):
    """Patch a single workflow JSON file."""
    with open(filepath, 'r') as f:
        workflow = json.load(f)

    filename = os.path.basename(filepath)
    modified = False

    # 1. Add errorWorkflow setting
    if "settings" not in workflow:
        workflow["settings"] = {}

    if workflow["settings"].get("errorWorkflow") != error_workflow_id:
        workflow["settings"]["errorWorkflow"] = error_workflow_id
        modified = True

    # 2. Check if this is a POST webhook that uses responseNode mode
    has_post_webhook = False
    has_error_response = False
    max_x = 0
    max_y = 300

    for node in workflow.get("nodes", []):
        # Track max position for placing new nodes
        pos = node.get("position", [0, 0])
        if pos[0] > max_x:
            max_x = pos[0]
            max_y = pos[1]

        # Check for POST webhook
        if node.get("type", "").endswith(".webhook"):
            method = node.get("parameters", {}).get("httpMethod", "GET")
            if method == "POST":
                has_post_webhook = True

        # Check for existing error response
        name = node.get("name", "").lower()
        if "error" in name and "respond" in node.get("type", ""):
            has_error_response = True

    # 3. For POST webhooks without error response, add one
    if has_post_webhook and not has_error_response:
        error_node = make_error_response_node(max_x + 200, max_y + 200)
        workflow["nodes"].append(error_node)
        modified = True

    if modified:
        with open(filepath, 'w') as f:
            json.dump(workflow, f, indent=2)
        return True

    return False


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 patch-webhook-error-handling.py <error_handler_workflow_id>")
        print("\nTo find the ID, import error-handler-global.json into n8n first,")
        print("then check the workflow list for its assigned ID.")
        sys.exit(1)

    error_workflow_id = sys.argv[1]
    webhook_files = sorted(glob.glob(str(WORKFLOWS_DIR / "*webhook*.json")))

    patched = 0
    skipped = 0
    errors = 0

    for filepath in webhook_files:
        filename = os.path.basename(filepath)

        if filename in SKIP_WORKFLOWS:
            print(f"  SKIP  {filename} (infrastructure)")
            skipped += 1
            continue

        try:
            if patch_workflow(filepath, error_workflow_id):
                print(f"  PATCH {filename}")
                patched += 1
            else:
                print(f"  OK    {filename} (already patched)")
                skipped += 1
        except Exception as e:
            print(f"  ERROR {filename}: {e}")
            errors += 1

    print(f"\nDone: {patched} patched, {skipped} skipped, {errors} errors")
    print(f"Total webhook workflows: {len(webhook_files)}")


if __name__ == "__main__":
    main()
