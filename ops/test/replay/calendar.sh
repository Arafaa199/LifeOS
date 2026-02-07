#!/usr/bin/env bash
# calendar.sh — Calendar domain replay tests
# Part of ops/test/replay/ framework
# Usage: calendar.sh [--json]
#
# Checks:
# 1. raw.calendar_events has recent data (within 48h)
# 2. life.v_daily_calendar_summary returns data for recent dates
# 3. dashboard.get_payload()->'calendar_summary' is not null
# 4. raw.reminders table exists and is queryable

set -uo pipefail

JSON_OUTPUT=false
[[ "${1:-}" == "--json" ]] && JSON_OUTPUT=true

DOMAIN="calendar"
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

# Check 1: raw.calendar_events freshness
RESULT=$(run_query "
  SELECT json_build_object(
    'age_hours', COALESCE(ROUND(EXTRACT(EPOCH FROM (NOW() - MAX(created_at))) / 3600, 1), -1),
    'total_rows', COUNT(*),
    'latest_date', COALESCE(MAX((start_at AT TIME ZONE 'Asia/Dubai')::date)::text, 'none')
  ) FROM raw.calendar_events;
")
Q_EXIT=$?

if [ $Q_EXIT -ne 0 ]; then
  add_check "events-freshness" "critical" "DB query failed"
else
  AGE=$(echo "$RESULT" | jq -r '.age_hours')
  ROWS=$(echo "$RESULT" | jq -r '.total_rows')
  LATEST=$(echo "$RESULT" | jq -r '.latest_date')

  if [ "$ROWS" = "0" ]; then
    add_check "events-freshness" "critical" "no calendar events in raw.calendar_events"
  elif (( $(echo "$AGE < 48" | bc -l) )); then
    add_check "events-freshness" "ok" "age=${AGE}h rows=$ROWS latest=$LATEST"
  elif (( $(echo "$AGE < 168" | bc -l) )); then
    add_check "events-freshness" "warn" "age=${AGE}h rows=$ROWS latest=$LATEST"
  else
    add_check "events-freshness" "critical" "age=${AGE}h rows=$ROWS latest=$LATEST"
  fi
fi

# Check 2: v_daily_calendar_summary returns data
RESULT2=$(run_query "
  SELECT json_build_object(
    'days_with_events', COUNT(*),
    'total_events', COALESCE(SUM(meeting_count), 0)
  ) FROM life.v_daily_calendar_summary
  WHERE day >= (CURRENT_DATE - INTERVAL '30 days');
")
Q_EXIT2=$?

if [ $Q_EXIT2 -ne 0 ]; then
  add_check "daily-summary" "critical" "v_daily_calendar_summary query failed"
else
  DAYS=$(echo "$RESULT2" | jq -r '.days_with_events')
  EVENTS=$(echo "$RESULT2" | jq -r '.total_events')

  if [ "$DAYS" = "0" ]; then
    add_check "daily-summary" "warn" "no calendar events in last 30 days"
  else
    add_check "daily-summary" "ok" "days_with_events=$DAYS total_events=$EVENTS (30d)"
  fi
fi

# Check 3: dashboard calendar_summary populated
RESULT3=$(run_query "
  SELECT (dashboard.get_payload()->'calendar_summary') IS NOT NULL AS has_summary;
")
Q_EXIT3=$?

if [ $Q_EXIT3 -ne 0 ]; then
  add_check "dashboard-payload" "critical" "dashboard.get_payload() query failed"
elif [ "$(echo "$RESULT3" | tr -d '[:space:]')" = "t" ]; then
  add_check "dashboard-payload" "ok" "calendar_summary present in payload"
else
  add_check "dashboard-payload" "critical" "calendar_summary missing from dashboard payload"
fi

# Check 4: raw.reminders table queryable
RESULT4=$(run_query "
  SELECT json_build_object(
    'total_rows', COUNT(*),
    'completed', COUNT(*) FILTER (WHERE is_completed = true)
  ) FROM raw.reminders;
")
Q_EXIT4=$?

if [ $Q_EXIT4 -ne 0 ]; then
  add_check "reminders-table" "critical" "raw.reminders query failed"
else
  REM_ROWS=$(echo "$RESULT4" | jq -r '.total_rows')
  REM_DONE=$(echo "$RESULT4" | jq -r '.completed')
  add_check "reminders-table" "ok" "rows=$REM_ROWS completed=$REM_DONE"
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
  echo "[$DOMAIN] Calendar Domain Replay Test"
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
