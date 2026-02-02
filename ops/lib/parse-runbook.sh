#!/usr/bin/env bash
# parse-runbook.sh — Extract check entries from runbook.yaml using grep/sed
# Output: one line per check: name|script|args|artifact|timeout|on_failure|critical
# No YAML parser needed — relies on consistent 2-space indent structure

set -uo pipefail

RUNBOOK="${1:?Usage: parse-runbook.sh <runbook.yaml>}"

if [ ! -f "$RUNBOOK" ]; then
  echo "ERROR: $RUNBOOK not found" >&2
  exit 1
fi

# Extract check blocks
current_check=""
script="" args="" artifact="" timeout="120" on_failure="log" critical="false"

flush() {
  if [ -n "$current_check" ] && [ -n "$script" ]; then
    echo "${current_check}|${script}|${args}|${artifact}|${timeout}|${on_failure}|${critical}"
  fi
  script="" args="" artifact="" timeout="120" on_failure="log" critical="false"
}

in_checks=false

while IFS= read -r line; do
  # Detect checks: section
  if echo "$line" | grep -q "^checks:"; then
    in_checks=true
    continue
  fi

  # Detect end of checks section (top-level key)
  if $in_checks && echo "$line" | grep -qE "^[a-z]" && ! echo "$line" | grep -q "^checks:"; then
    flush
    in_checks=false
    continue
  fi

  if ! $in_checks; then continue; fi

  # Check name (2-space indent, ends with colon)
  if echo "$line" | grep -qE "^  [a-z][a-z0-9_-]+:$"; then
    flush
    current_check=$(echo "$line" | sed 's/^  //;s/:$//')
    continue
  fi

  # Fields (4-space indent)
  val=$(echo "$line" | sed 's/^    //')
  case "$val" in
    script:*)     script=$(echo "$val" | sed 's/script: *"//;s/"$//') ;;
    args:*)       args=$(echo "$val" | sed 's/args: *\[//;s/\]$//;s/"//g;s/, */ /g') ;;
    artifact:*)   artifact=$(echo "$val" | sed 's/artifact: *"//;s/"$//') ;;
    timeout_seconds:*) timeout=$(echo "$val" | sed 's/timeout_seconds: *//') ;;
    on_failure:*) on_failure=$(echo "$val" | sed 's/on_failure: *//') ;;
    critical:*)   critical=$(echo "$val" | sed 's/critical: *//') ;;
  esac
done < "$RUNBOOK"

flush
