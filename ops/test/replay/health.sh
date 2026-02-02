#!/usr/bin/env bash
# health.sh — Health domain replay tests
# Part of ops/test/replay/ framework
# Usage: health.sh [--json]
#
# Checks WHOOP data freshness via direct DB query

set -uo pipefail

JSON_OUTPUT=false
[[ "${1:-}" == "--json" ]] && JSON_OUTPUT=true

DOMAIN="health"

# Query WHOOP data age
RESULT=$(ssh -o ConnectTimeout=5 nexus \
  "docker exec nexus-db psql -U nexus -d nexus -t -A -c \"
    SELECT json_build_object(
      'whoop_age_hours', ROUND(EXTRACT(EPOCH FROM (NOW() - MAX(created_at))) / 3600, 1),
      'whoop_rows', COUNT(*),
      'latest_date', MAX(date)::text
    ) FROM health.whoop_recovery;
  \"" 2>&1)
QUERY_EXIT=$?

if [ $QUERY_EXIT -ne 0 ]; then
  STATUS="critical"
  DETAIL="DB query failed"
else
  AGE=$(echo "$RESULT" | jq -r '.whoop_age_hours')
  ROWS=$(echo "$RESULT" | jq -r '.whoop_rows')
  if (( $(echo "$AGE < 4" | bc -l) )); then
    STATUS="healthy"
  elif (( $(echo "$AGE < 12" | bc -l) )); then
    STATUS="stale"
  else
    STATUS="critical"
  fi
  DETAIL="age=${AGE}h rows=$ROWS"
fi

if $JSON_OUTPUT; then
  cat <<EOF
{
  "domain": "$DOMAIN",
  "test": "whoop-freshness",
  "status": "$STATUS",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "detail": "$DETAIL",
  "exit_code": $QUERY_EXIT
}
EOF
else
  echo "[$DOMAIN] WHOOP Data Freshness"
  echo "Status: $STATUS ($DETAIL)"
fi

[ "$STATUS" = "critical" ] && exit 1
exit 0
