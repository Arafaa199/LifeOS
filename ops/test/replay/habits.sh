#!/usr/bin/env bash
# habits.sh — Habits domain replay tests
# Part of ops/test/replay/ framework
# Usage: habits.sh [--json]
#
# Checks:
# 1. life.habits has active habits defined
# 2. life.habit_completions freshness (within 48h threshold)
# 3. dashboard.get_payload()->'habits_today' is not null and is an array
# 4. life.get_habit_streaks(id) returns valid data for at least one habit

set -uo pipefail

JSON_OUTPUT=false
[[ "${1:-}" == "--json" ]] && JSON_OUTPUT=true

DOMAIN="habits"
CHECKS=()
OVERALL="ok"

run_query() {
  ssh -o ConnectTimeout=5 nexus \
    "docker exec nexus-db psql -U nexus -d nexus -t -A -c \"$1\"" 2>&1
}

add_check() {
  local name="$1" status="$2" detail="$3"
  CHECKS+=("{\"name\":\"$name\",\"status\":\"$status\",\"detail\":\"$detail\"}")
  if [ "$status" = "critical" ] && [ "$OVERALL" != "critical" ]; then
    OVERALL="critical"
  elif [ "$status" = "warn" ] && [ "$OVERALL" = "ok" ]; then
    OVERALL="warn"
  fi
}

# Check 1: life.habits has active habits
RESULT=$(run_query "
  SELECT json_build_object(
    'active_count', COUNT(*) FILTER (WHERE is_active),
    'total_count', COUNT(*)
  ) FROM life.habits;
")
Q_EXIT=$?

if [ $Q_EXIT -ne 0 ]; then
  add_check "active-habits" "critical" "DB query failed"
else
  ACTIVE=$(echo "$RESULT" | jq -r '.active_count')
  TOTAL=$(echo "$RESULT" | jq -r '.total_count')

  if [ "$TOTAL" = "0" ]; then
    add_check "active-habits" "critical" "no habits defined in life.habits"
  elif [ "$ACTIVE" = "0" ]; then
    add_check "active-habits" "warn" "no active habits (total=$TOTAL)"
  else
    add_check "active-habits" "ok" "active=$ACTIVE total=$TOTAL"
  fi
fi

# Check 2: life.habit_completions freshness
RESULT2=$(run_query "
  SELECT json_build_object(
    'age_hours', COALESCE(ROUND(EXTRACT(EPOCH FROM (NOW() - MAX(completed_at))) / 3600, 1), -1),
    'total_rows', COUNT(*),
    'latest_date', COALESCE(MAX(completed_at::date)::text, 'none')
  ) FROM life.habit_completions;
")
Q_EXIT2=$?

if [ $Q_EXIT2 -ne 0 ]; then
  add_check "completions-freshness" "critical" "habit_completions query failed"
else
  AGE=$(echo "$RESULT2" | jq -r '.age_hours')
  ROWS=$(echo "$RESULT2" | jq -r '.total_rows')
  LATEST=$(echo "$RESULT2" | jq -r '.latest_date')

  if [ "$ROWS" = "0" ]; then
    add_check "completions-freshness" "warn" "no habit completions yet"
  elif (( $(echo "$AGE < 48" | bc -l) )); then
    add_check "completions-freshness" "ok" "age=${AGE}h rows=$ROWS latest=$LATEST"
  elif (( $(echo "$AGE < 168" | bc -l) )); then
    add_check "completions-freshness" "warn" "age=${AGE}h rows=$ROWS latest=$LATEST"
  else
    add_check "completions-freshness" "critical" "age=${AGE}h rows=$ROWS latest=$LATEST"
  fi
fi

# Check 3: dashboard habits_today populated
RESULT3=$(run_query "
  SELECT json_build_object(
    'has_key', (dashboard.get_payload()->'habits_today') IS NOT NULL,
    'is_array', jsonb_typeof(dashboard.get_payload()->'habits_today') = 'array',
    'count', jsonb_array_length(COALESCE(dashboard.get_payload()->'habits_today', '[]'::jsonb))
  );
")
Q_EXIT3=$?

if [ $Q_EXIT3 -ne 0 ]; then
  add_check "dashboard-payload" "critical" "dashboard.get_payload() query failed"
else
  HAS_KEY=$(echo "$RESULT3" | jq -r '.has_key')
  IS_ARRAY=$(echo "$RESULT3" | jq -r '.is_array')
  COUNT=$(echo "$RESULT3" | jq -r '.count')

  if [ "$HAS_KEY" = "true" ] && [ "$IS_ARRAY" = "true" ]; then
    add_check "dashboard-payload" "ok" "habits_today present, $COUNT habits in array"
  elif [ "$HAS_KEY" = "true" ]; then
    add_check "dashboard-payload" "warn" "habits_today present but not an array"
  else
    add_check "dashboard-payload" "critical" "habits_today missing from dashboard payload"
  fi
fi

# Check 4: life.get_habit_streaks() returns valid data
RESULT4=$(run_query "
  SELECT json_build_object(
    'habits_with_streaks', COUNT(*),
    'max_streak', COALESCE(MAX(s.current_streak), 0)
  ) FROM (SELECT id FROM life.habits WHERE is_active LIMIT 5) h,
  LATERAL life.get_habit_streaks(h.id) s;
")
Q_EXIT4=$?

if [ $Q_EXIT4 -ne 0 ]; then
  add_check "streak-function" "critical" "get_habit_streaks() query failed"
else
  STREAK_COUNT=$(echo "$RESULT4" | jq -r '.habits_with_streaks')
  MAX_STREAK=$(echo "$RESULT4" | jq -r '.max_streak')

  if [ "$STREAK_COUNT" = "0" ]; then
    add_check "streak-function" "warn" "no streak data returned (may need completions)"
  else
    add_check "streak-function" "ok" "habits_with_streaks=$STREAK_COUNT max_streak=$MAX_STREAK"
  fi
fi

# Output
CHECKS_JSON=$(printf '%s,' "${CHECKS[@]}" | sed 's/,$//')

if $JSON_OUTPUT; then
  cat <<EOF
{
  "domain": "$DOMAIN",
  "status": "$OVERALL",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "checks": [$CHECKS_JSON]
}
EOF
else
  echo "[$DOMAIN] Habits Domain Replay Test"
  for check in "${CHECKS[@]}"; do
    NAME=$(echo "$check" | jq -r '.name')
    STAT=$(echo "$check" | jq -r '.status')
    DET=$(echo "$check" | jq -r '.detail')
    if [ "$STAT" = "ok" ]; then
      echo "  PASS  $NAME — $DET"
    elif [ "$STAT" = "warn" ]; then
      echo "  WARN  $NAME — $DET"
    else
      echo "  FAIL  $NAME — $DET"
    fi
  done
  echo ""
  echo "Overall: $OVERALL"
fi

[ "$OVERALL" = "critical" ] && exit 1
exit 0
