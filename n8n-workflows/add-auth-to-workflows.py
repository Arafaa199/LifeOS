#!/usr/bin/env python3
"""
Add API authentication to all n8n webhook workflows.
Creates modified copies in ./with-auth/ directory.
"""

import json
import os
from pathlib import Path

WORKFLOW_DIR = Path(__file__).parent
OUTPUT_DIR = WORKFLOW_DIR / "with-auth"
SKIP_FILES = {"API_AUTH_EXAMPLE.json", "add-auth-to-workflows.py"}

# Auth nodes to insert
AUTH_CHECK_NODE = {
    "parameters": {
        "conditions": {
            "string": [
                {
                    "value1": "={{ $json.headers['x-api-key'] }}",
                    "operation": "equals",
                    "value2": "={{ $env.NEXUS_API_KEY }}"
                }
            ]
        }
    },
    "name": "Check API Key",
    "type": "n8n-nodes-base.if",
    "typeVersion": 1,
    "position": [0, 0]  # Will be set dynamically
}

UNAUTHORIZED_NODE = {
    "parameters": {
        "respondWith": "json",
        "responseBody": "={\"success\": false, \"error\": \"Unauthorized - Invalid API Key\"}",
        "options": {
            "responseCode": 401
        }
    },
    "name": "Unauthorized",
    "type": "n8n-nodes-base.respondToWebhook",
    "typeVersion": 1,
    "position": [0, 0]  # Will be set dynamically
}


def find_webhook_node(nodes):
    """Find the webhook trigger node."""
    for i, node in enumerate(nodes):
        if node.get("type") == "n8n-nodes-base.webhook":
            return i, node
    return None, None


def add_auth_to_workflow(workflow):
    """Add auth check after webhook node."""
    nodes = workflow.get("nodes", [])
    connections = workflow.get("connections", {})

    webhook_idx, webhook_node = find_webhook_node(nodes)
    if webhook_node is None:
        return None, "No webhook node found"

    webhook_name = webhook_node.get("name", "Webhook")
    webhook_pos = webhook_node.get("position", [250, 300])

    # Check if auth already exists
    for node in nodes:
        if node.get("name") == "Check API Key":
            return None, "Auth already exists"

    # Create auth check node (200px to the right of webhook)
    auth_node = AUTH_CHECK_NODE.copy()
    auth_node["parameters"] = AUTH_CHECK_NODE["parameters"].copy()
    auth_node["position"] = [webhook_pos[0] + 200, webhook_pos[1]]

    # Create unauthorized response node (200px right and 150px down from auth)
    unauth_node = UNAUTHORIZED_NODE.copy()
    unauth_node["parameters"] = UNAUTHORIZED_NODE["parameters"].copy()
    unauth_node["position"] = [webhook_pos[0] + 400, webhook_pos[1] + 150]

    # Shift all nodes to the right to make room
    for node in nodes:
        if node.get("name") != webhook_name:
            pos = node.get("position", [0, 0])
            node["position"] = [pos[0] + 200, pos[1]]

    # Get existing connections from webhook
    webhook_connections = connections.get(webhook_name, {}).get("main", [[]])
    existing_targets = webhook_connections[0] if webhook_connections else []

    # Rewire: Webhook → Check API Key
    connections[webhook_name] = {
        "main": [[{"node": "Check API Key", "type": "main", "index": 0}]]
    }

    # Check API Key → (true) existing targets, (false) Unauthorized
    connections["Check API Key"] = {
        "main": [
            existing_targets,  # True branch - original targets
            [{"node": "Unauthorized", "type": "main", "index": 0}]  # False branch
        ]
    }

    # Add new nodes
    nodes.append(auth_node)
    nodes.append(unauth_node)

    workflow["nodes"] = nodes
    workflow["connections"] = connections

    return workflow, "OK"


def process_workflows():
    """Process all workflow files."""
    OUTPUT_DIR.mkdir(exist_ok=True)

    results = []
    for filepath in WORKFLOW_DIR.glob("*.json"):
        if filepath.name in SKIP_FILES:
            continue
        if filepath.name.startswith("."):
            continue

        try:
            with open(filepath, "r") as f:
                workflow = json.load(f)

            modified, status = add_auth_to_workflow(workflow)

            if modified:
                output_path = OUTPUT_DIR / filepath.name
                with open(output_path, "w") as f:
                    json.dump(modified, f, indent=2)
                results.append((filepath.name, "✅ Modified", str(output_path)))
            else:
                results.append((filepath.name, f"⏭️  Skipped: {status}", ""))

        except Exception as e:
            results.append((filepath.name, f"❌ Error: {e}", ""))

    return results


if __name__ == "__main__":
    print("Adding API authentication to n8n workflows...")
    print(f"Output directory: {OUTPUT_DIR}\n")

    results = process_workflows()

    modified_count = 0
    for name, status, path in results:
        print(f"{name}: {status}")
        if "Modified" in status:
            modified_count += 1

    print(f"\n{'='*50}")
    print(f"Modified: {modified_count} workflows")
    print(f"Output: {OUTPUT_DIR}/")
    print("\nNext steps:")
    print("1. Review the modified workflows in with-auth/")
    print("2. Import to n8n: n8n.rfanw → Settings → Import from File")
    print("3. Add NEXUS_API_KEY to n8n environment variables")
    print("4. Test: curl -H 'X-API-Key: <key>' https://n8n.rfanw/webhook/nexus-finance-summary")
