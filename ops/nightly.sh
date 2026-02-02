#!/usr/bin/env bash
# nightly.sh — LifeOS nightly ops runner
# Iterates ops/runbook.yaml checks, saves reports, notifies on failure
# Usage: nightly.sh [--dry-run]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTS_DIR="$SCRIPT_DIR/reports"
RUNBOOK="$SCRIPT_DIR/runbook.yaml"
PARSER="$SCRIPT_DIR/lib/parse-runbook.sh"
TODAY=$(date +%Y-%m-%d)
MD_REPORT="$REPORTS_DIR/ops-report-${TODAY}.md"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

mkdir -p "$REPORTS_DIR"

if [ ! -f "$RUNBOOK" ]; then
  echo "ERROR: runbook.yaml not found at $RUNBOOK"
  exit 1
fi

if [ ! -f "$PARSER" ]; then
  echo "ERROR: parse-runbook.sh not found at $PARSER"
  exit 1
fi

# ── Parse runbook and execute checks ─────────────────────────────

TOTAL=0
PASSED=0
FAILED=0
FAIL_NAMES=()
MD_SECTIONS=()

while IFS='|' read -r name script args artifact timeout on_failure critical; do
  TOTAL=$((TOTAL + 1))

  # Resolve paths relative to repo root
  FULL_SCRIPT="$SCRIPT_DIR/../$script"
  if [ ! -f "$FULL_SCRIPT" ]; then
    # Try relative to SCRIPT_DIR
    FULL_SCRIPT="$SCRIPT_DIR/$script"
  fi
  if [ ! -f "$FULL_SCRIPT" ]; then
    FULL_SCRIPT="$SCRIPT_DIR/../$script"
  fi

  # Resolve artifact path
  ARTIFACT_PATH=$(echo "$artifact" | sed "s/{date}/$TODAY/g")
  FULL_ARTIFACT="$SCRIPT_DIR/../$ARTIFACT_PATH"

  echo "── [$name] ──────────────────────────────────"

  if $DRY_RUN; then
    echo "  DRY RUN: would run: bash $FULL_SCRIPT $args"
    echo "  Artifact: $FULL_ARTIFACT"
    PASSED=$((PASSED + 1))
    continue
  fi

  if [ ! -f "$FULL_SCRIPT" ]; then
    echo "  SKIP: script not found: $script"
    MD_SECTIONS+=("### $name\n**Status:** skip — script not found\n")
    continue
  fi

  # Execute with timeout
  START_TS=$(date +%s)
  # shellcheck disable=SC2086
  OUTPUT=$(timeout "$timeout" bash "$FULL_SCRIPT" $args 2>&1)
  EXIT_CODE=$?
  END_TS=$(date +%s)
  DURATION=$((END_TS - START_TS))

  # Save artifact if script produced JSON output
  if echo "$OUTPUT" | jq . >/dev/null 2>&1; then
    mkdir -p "$(dirname "$FULL_ARTIFACT")"
    echo "$OUTPUT" > "$FULL_ARTIFACT"
    echo "  Artifact saved: $ARTIFACT_PATH"
  fi

  if [ $EXIT_CODE -eq 0 ]; then
    echo "  PASS (${DURATION}s)"
    PASSED=$((PASSED + 1))
    MD_SECTIONS+=("### $name\n**Status:** healthy (${DURATION}s)\n")
  else
    echo "  FAIL (exit $EXIT_CODE, ${DURATION}s)"
    FAILED=$((FAILED + 1))
    FAIL_NAMES+=("$name")

    # Extract summary from JSON output if possible
    DETAIL=""
    if echo "$OUTPUT" | jq -e '.failed' >/dev/null 2>&1; then
      FAIL_COUNT=$(echo "$OUTPUT" | jq -r '.failed')
      DETAIL="$FAIL_COUNT sub-checks failed"
    fi

    MD_SECTIONS+=("### $name\n**Status:** critical (exit $EXIT_CODE, ${DURATION}s)\n${DETAIL:+Detail: $DETAIL\n}")
  fi

done < <(bash "$PARSER" "$RUNBOOK")

# ── Generate markdown report ─────────────────────────────────────

{
  echo "# LifeOS Ops Report — $TODAY"
  echo ""
  echo "## Summary"
  echo "- Total checks: $TOTAL"
  echo "- Passed: $PASSED"
  echo "- Failed: $FAILED"
  echo ""
  echo "## Checks"
  for section in "${MD_SECTIONS[@]}"; do
    echo -e "$section"
  done
  echo "---"
  echo "Generated at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$MD_REPORT"

echo ""
echo "Report: $MD_REPORT"
echo "Total: $TOTAL | Pass: $PASSED | Fail: $FAILED"

# ── Notify on failure ────────────────────────────────────────────

if [ "$FAILED" -gt 0 ] && ! $DRY_RUN; then
  FAIL_LIST=$(IFS=', '; echo "${FAIL_NAMES[*]}")
  osascript -e "display notification \"$FAILED check(s) failed: $FAIL_LIST\" with title \"LifeOS Ops\" subtitle \"Nightly Report\"" 2>/dev/null || true
  exit 1
fi

exit 0
