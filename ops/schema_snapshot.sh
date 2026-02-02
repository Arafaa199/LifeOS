#!/usr/bin/env bash
# schema_snapshot.sh — Nightly schema diff tracking for nexus database
# Usage: schema_snapshot.sh [--quiet]
# Saves pg_dump -s output, diffs against previous, keeps last 7

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOTS_DIR="$SCRIPT_DIR/snapshots"
QUIET=false
[[ "${1:-}" == "--quiet" ]] && QUIET=true

TODAY=$(date +%Y-%m-%d)
SNAPSHOT_FILE="$SNAPSHOTS_DIR/schema-${TODAY}.sql"
DIFF_FILE="$SNAPSHOTS_DIR/schema-diff-${TODAY}.txt"

mkdir -p "$SNAPSHOTS_DIR"

# Dump schema (structure only, no data)
$QUIET || echo "Dumping schema from nexus-db..."
if ! ssh -o ConnectTimeout=10 nexus \
  "docker exec nexus-db pg_dump -U nexus -d nexus -s --no-owner --no-privileges" \
  > "$SNAPSHOT_FILE" 2>/dev/null; then
  echo "ERROR: Failed to dump schema from nexus-db"
  exit 1
fi

# Verify non-empty dump
if [ ! -s "$SNAPSHOT_FILE" ]; then
  echo "ERROR: Schema dump is empty"
  exit 1
fi

$QUIET || echo "Saved: $SNAPSHOT_FILE ($(wc -l < "$SNAPSHOT_FILE") lines)"

# Find previous snapshot (most recent before today)
PREV_SNAPSHOT=$(ls -1 "$SNAPSHOTS_DIR"/schema-*.sql 2>/dev/null \
  | grep -v "$TODAY" \
  | sort -r \
  | head -1)

if [ -n "$PREV_SNAPSHOT" ]; then
  PREV_DATE=$(basename "$PREV_SNAPSHOT" .sql | sed 's/schema-//')
  diff "$PREV_SNAPSHOT" "$SNAPSHOT_FILE" > "$DIFF_FILE" 2>&1 || true

  if [ -s "$DIFF_FILE" ]; then
    CHANGES=$(grep -c "^[<>]" "$DIFF_FILE" 2>/dev/null || echo 0)
    $QUIET || echo "Schema diff: $CHANGES changed lines vs $PREV_DATE"
    echo "Schema diff: $CHANGES changed lines vs $PREV_DATE"
  else
    $QUIET || echo "No schema changes since $PREV_DATE"
    rm -f "$DIFF_FILE"
  fi
else
  $QUIET || echo "First snapshot — no diff available"
fi

# Cleanup: keep last 7 snapshots, move older to Trash
SNAPSHOT_COUNT=$(ls -1 "$SNAPSHOTS_DIR"/schema-*.sql 2>/dev/null | wc -l)
if [ "$SNAPSHOT_COUNT" -gt 7 ]; then
  ls -1t "$SNAPSHOTS_DIR"/schema-*.sql | tail -n +8 | while read -r old_file; do
    $QUIET || echo "Moving old snapshot to Trash: $(basename "$old_file")"
    mv "$old_file" ~/.Trash/
  done
  # Also clean old diffs
  ls -1t "$SNAPSHOTS_DIR"/schema-diff-*.txt 2>/dev/null | tail -n +8 | while read -r old_file; do
    mv "$old_file" ~/.Trash/
  done
fi

$QUIET || echo "Done."
