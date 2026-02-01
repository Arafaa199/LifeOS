#!/usr/bin/env python3
"""
Obsidian Vault Indexer for Nexus

Walks an Obsidian vault directory, extracts metadata from .md files
(YAML frontmatter, title, tags, word count), and upserts into
raw.notes_index via n8n webhook.

Incremental: only re-indexes files with mtime > last indexed_at.
Marks files no longer on disk as removed.

Dependencies: None (stdlib only)

Usage:
    python3 index-obsidian-vault.py [--vault-path PATH] [--vault-name NAME] [--full]
"""

import argparse
import json
import os
import re
import sys
import urllib.request
import urllib.error
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_VAULT_PATH = os.path.expanduser(
    "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/RafaVault"
)
DEFAULT_VAULT_NAME = "RafaVault"
WEBHOOK_BASE = os.environ.get("WEBHOOK_BASE_URL", "https://n8n.rfanw")
API_KEY = os.environ.get("NEXUS_API_KEY", "")

SKIP_DIRS = {".obsidian", ".trash", ".stversions", ".git", "node_modules"}
FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)
HEADING_RE = re.compile(r"^#\s+(.+)$", re.MULTILINE)


def parse_frontmatter(content: str) -> dict:
    """Parse YAML frontmatter from markdown content using regex (no pyyaml dependency)."""
    match = FRONTMATTER_RE.match(content)
    if not match:
        return {}

    fm_text = match.group(1)
    result = {}

    for line in fm_text.split("\n"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue

        if ":" not in line:
            continue

        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip()

        if not value:
            continue

        # Handle YAML arrays: [item1, item2] or - item
        if value.startswith("[") and value.endswith("]"):
            items = [i.strip().strip("'\"") for i in value[1:-1].split(",")]
            result[key] = [i for i in items if i]
        elif value.startswith("'") or value.startswith('"'):
            result[key] = value.strip("'\"")
        else:
            # Try numeric
            try:
                if "." in value:
                    result[key] = float(value)
                else:
                    result[key] = int(value)
            except ValueError:
                # Boolean
                if value.lower() in ("true", "yes"):
                    result[key] = True
                elif value.lower() in ("false", "no"):
                    result[key] = False
                else:
                    result[key] = value

    return result


def extract_title(content: str, frontmatter: dict, filename: str) -> str:
    """Extract title from frontmatter, first heading, or filename."""
    if "title" in frontmatter:
        return str(frontmatter["title"])

    match = HEADING_RE.search(content)
    if match:
        return match.group(1).strip()

    return Path(filename).stem


def extract_tags(frontmatter: dict) -> list:
    """Extract tags from frontmatter."""
    tags = frontmatter.get("tags", [])
    if isinstance(tags, str):
        tags = [t.strip() for t in tags.split(",")]
    if isinstance(tags, list):
        return [str(t).strip().strip("#") for t in tags if t]
    return []


def count_words(content: str) -> int:
    """Count words in content, excluding frontmatter."""
    text = FRONTMATTER_RE.sub("", content)
    return len(text.split())


def scan_vault(vault_path: str) -> list:
    """Walk vault and collect all .md file metadata."""
    vault = Path(vault_path)
    files = []

    for md_file in vault.rglob("*.md"):
        # Skip hidden/excluded directories
        parts = md_file.relative_to(vault).parts
        if any(p in SKIP_DIRS or p.startswith(".") for p in parts[:-1]):
            continue

        relative_path = str(md_file.relative_to(vault))
        stat = md_file.stat()
        mtime = datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc)

        try:
            content = md_file.read_text(encoding="utf-8", errors="replace")
        except Exception as e:
            print(f"[WARN] Could not read {relative_path}: {e}", file=sys.stderr)
            continue

        frontmatter = parse_frontmatter(content)
        title = extract_title(content, frontmatter, md_file.name)
        tags = extract_tags(frontmatter)
        word_count = count_words(content)

        files.append({
            "relative_path": relative_path,
            "title": title,
            "tags": tags,
            "frontmatter": frontmatter,
            "word_count": word_count,
            "file_modified_at": mtime.isoformat(),
        })

    return files


def send_to_webhook(vault_name: str, files: list, all_paths: list) -> dict:
    """Send indexed files to n8n webhook for DB upsert."""
    url = f"{WEBHOOK_BASE}/webhook/nexus-notes-index"

    payload = {
        "vault": vault_name,
        "files": files,
        "all_paths": all_paths,
    }

    data = json.dumps(payload).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "X-API-Key": API_KEY,
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            body = json.loads(resp.read().decode("utf-8"))
            return body
    except urllib.error.HTTPError as e:
        print(f"[ERROR] Webhook HTTP {e.code}: {e.read().decode()}", file=sys.stderr)
        return {"success": False, "error": str(e)}
    except urllib.error.URLError as e:
        print(f"[ERROR] Webhook connection failed: {e}", file=sys.stderr)
        return {"success": False, "error": str(e)}


def main():
    parser = argparse.ArgumentParser(description="Index Obsidian vault into Nexus DB")
    parser.add_argument("--vault-path", default=DEFAULT_VAULT_PATH, help="Path to vault")
    parser.add_argument("--vault-name", default=DEFAULT_VAULT_NAME, help="Vault name in DB")
    parser.add_argument("--full", action="store_true", help="Full re-index (ignore mtime)")
    parser.add_argument("--dry-run", action="store_true", help="Scan only, don't send")
    args = parser.parse_args()

    vault_path = args.vault_path
    if not os.path.isdir(vault_path):
        print(f"[ERROR] Vault not found: {vault_path}", file=sys.stderr)
        sys.exit(1)

    print(f"[INFO] Scanning vault: {vault_path}")
    files = scan_vault(vault_path)
    all_paths = [f["relative_path"] for f in files]
    print(f"[INFO] Found {len(files)} markdown files")

    if args.dry_run:
        for f in files[:10]:
            print(f"  {f['relative_path']} ({f['word_count']} words, tags={f['tags']})")
        if len(files) > 10:
            print(f"  ... and {len(files) - 10} more")
        return

    if not files:
        print("[INFO] No files to index")
        return

    # Send in batches of 100
    batch_size = 100
    total_indexed = 0

    for i in range(0, len(files), batch_size):
        batch = files[i : i + batch_size]
        # Only send all_paths on the last batch (for removal detection)
        paths_for_batch = all_paths if i + batch_size >= len(files) else []

        result = send_to_webhook(args.vault_name, batch, paths_for_batch)

        if result.get("success"):
            indexed = result.get("indexed", len(batch))
            removed = result.get("removed", 0)
            total_indexed += indexed
            print(f"[INFO] Batch {i // batch_size + 1}: indexed={indexed}, removed={removed}")
        else:
            print(f"[ERROR] Batch {i // batch_size + 1} failed: {result.get('error', 'unknown')}", file=sys.stderr)

    print(f"[INFO] Done. Total indexed: {total_indexed}/{len(files)}")


if __name__ == "__main__":
    main()
