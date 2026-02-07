#!/usr/bin/env bash
# nutrition.sh — Nutrition domain replay tests
# Part of ops/test/replay/ framework
# Usage: nutrition.sh [--json]
#
# Checks food_log, water_log freshness and dashboard nutrition data

set -uo pipefail

JSON_OUTPUT=false
[[ "${1:-}" == "--json" ]] && JSON_OUTPUT=true

DOMAIN="nutrition"

# Query nutrition data freshness
RESULT=$(ssh -o ConnectTimeout=5 nexus \
  "docker exec nexus-db psql -U nexus -d nexus -t -A -c \"
    SELECT json_build_object(
      'food_age_hours', COALESCE(ROUND(EXTRACT(EPOCH FROM (NOW() - (SELECT MAX(logged_at) FROM nutrition.food_log))) / 3600, 1), -1),
      'food_rows_today', (SELECT COUNT(*) FROM nutrition.food_log WHERE date = (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Dubai')::date),
      'water_age_hours', COALESCE(ROUND(EXTRACT(EPOCH FROM (NOW() - (SELECT MAX(logged_at) FROM nutrition.water_log))) / 3600, 1), -1),
      'water_ml_today', COALESCE((SELECT SUM(amount_ml) FROM nutrition.water_log WHERE date = (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Dubai')::date), 0),
      'daily_facts_calories', (SELECT calories_consumed FROM life.daily_facts WHERE day = (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Dubai')::date),
      'daily_facts_water', (SELECT water_ml FROM life.daily_facts WHERE day = (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Dubai')::date)
    );
  \"" 2>&1)
QUERY_EXIT=$?

if [ $QUERY_EXIT -ne 0 ]; then
  STATUS="critical"
  DETAIL="DB query failed"
else
  FOOD_AGE=$(echo "$RESULT" | jq -r '.food_age_hours')
  WATER_AGE=$(echo "$RESULT" | jq -r '.water_age_hours')
  FOOD_TODAY=$(echo "$RESULT" | jq -r '.food_rows_today')
  WATER_TODAY=$(echo "$RESULT" | jq -r '.water_ml_today')
  DF_CALORIES=$(echo "$RESULT" | jq -r '.daily_facts_calories')
  DF_WATER=$(echo "$RESULT" | jq -r '.daily_facts_water')

  # Determine status based on data freshness (24h threshold for nutrition)
  if [ "$FOOD_AGE" = "-1" ] || [ "$WATER_AGE" = "-1" ]; then
    STATUS="critical"
    DETAIL="no data found"
  elif (( $(echo "$FOOD_AGE < 24 && $WATER_AGE < 24" | bc -l) )); then
    STATUS="healthy"
    DETAIL="food=${FOOD_AGE}h water=${WATER_AGE}h today_food=$FOOD_TODAY water_ml=$WATER_TODAY"
  elif (( $(echo "$FOOD_AGE < 48 || $WATER_AGE < 48" | bc -l) )); then
    STATUS="stale"
    DETAIL="food=${FOOD_AGE}h water=${WATER_AGE}h (stale)"
  else
    STATUS="critical"
    DETAIL="food=${FOOD_AGE}h water=${WATER_AGE}h (no recent data)"
  fi
fi

if $JSON_OUTPUT; then
  cat <<EOF
{
  "domain": "$DOMAIN",
  "test": "nutrition-freshness",
  "status": "$STATUS",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "detail": "$DETAIL",
  "exit_code": $QUERY_EXIT
}
EOF
else
  echo "[$DOMAIN] Nutrition Data Freshness"
  echo "Status: $STATUS ($DETAIL)"
fi

[ "$STATUS" = "critical" ] && exit 1
exit 0
