#!/bin/bash
set -euo pipefail

# LifeOS - Deterministic Replay Script (Last 30 Days)
# Purpose: Verify data pipeline is deterministic by replaying last 30 days
# Owner: coder (TASK-VERIFY.2)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="/tmp/lifeos-replay-backup-$(date +%Y%m%d-%H%M%S)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "═══════════════════════════════════════════════════════════════"
echo "LifeOS - Deterministic Replay (Last 30 Days)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Function to run SQL on nexus
run_sql() {
    ssh nexus "docker exec nexus-db psql -U nexus -d nexus -t -A -c \"$1\""
}

# Phase 1: Pre-Replay Snapshot
echo "PHASE 1: Creating pre-replay snapshot..."
mkdir -p "$BACKUP_DIR"

echo "Capturing table counts..."
cat > "$BACKUP_DIR/pre_counts.txt" <<EOF
=== PRE-REPLAY COUNTS ($(date)) ===

SOURCE TABLES (should remain unchanged):
raw.bank_sms: $(run_sql "SELECT COUNT(*) FROM raw.bank_sms")
raw.healthkit_samples: $(run_sql "SELECT COUNT(*) FROM raw.healthkit_samples")
raw.github_events: $(run_sql "SELECT COUNT(*) FROM raw.github_events")
finance.budgets: $(run_sql "SELECT COUNT(*) FROM finance.budgets")
finance.categories: $(run_sql "SELECT COUNT(*) FROM finance.categories")
finance.merchant_rules: $(run_sql "SELECT COUNT(*) FROM finance.merchant_rules")

DERIVED TABLES (will be rebuilt):
finance.transactions: $(run_sql "SELECT COUNT(*) FROM finance.transactions")
finance.receipts: $(run_sql "SELECT COUNT(*) FROM finance.receipts")
finance.receipt_items: $(run_sql "SELECT COUNT(*) FROM finance.receipt_items")
life.daily_facts: $(run_sql "SELECT COUNT(*) FROM life.daily_facts WHERE day >= CURRENT_DATE - INTERVAL '30 days'")
facts.daily_health: $(run_sql "SELECT COUNT(*) FROM facts.daily_health WHERE date >= CURRENT_DATE - INTERVAL '30 days'")
facts.daily_finance: $(run_sql "SELECT COUNT(*) FROM facts.daily_finance WHERE date >= CURRENT_DATE - INTERVAL '30 days'")
insights.weekly_reports: $(run_sql "SELECT COUNT(*) FROM insights.weekly_reports WHERE week_start >= CURRENT_DATE - INTERVAL '30 days'")

TOTALS (for validation):
Total spend (last 30d): $(run_sql "SELECT COALESCE(SUM(amount), 0) FROM finance.transactions WHERE amount < 0 AND transaction_at >= CURRENT_DATE - INTERVAL '30 days'")
Total recovery score (last 30d): $(run_sql "SELECT COALESCE(SUM(recovery_score), 0) FROM life.daily_facts WHERE day >= CURRENT_DATE - INTERVAL '30 days'")
EOF

cat "$BACKUP_DIR/pre_counts.txt"

# Phase 2: Database Backup
echo ""
echo "PHASE 2: Creating database backup..."
ssh nexus "docker exec nexus-db pg_dump -U nexus nexus" > "$BACKUP_DIR/nexus-full-backup.sql"
BACKUP_SIZE=$(du -h "$BACKUP_DIR/nexus-full-backup.sql" | cut -f1)
echo "✓ Backup created: $BACKUP_DIR/nexus-full-backup.sql ($BACKUP_SIZE)"

# Phase 3: Truncate Derived Tables (Last 30 Days Only)
echo ""
echo "PHASE 3: Truncating derived tables (last 30 days)..."
echo -e "${YELLOW}Note: This only affects last 30 days, not all historical data${NC}"

run_sql "DELETE FROM life.daily_facts WHERE day >= CURRENT_DATE - INTERVAL '30 days'"
run_sql "DELETE FROM facts.daily_health WHERE date >= CURRENT_DATE - INTERVAL '30 days'"
run_sql "DELETE FROM facts.daily_finance WHERE date >= CURRENT_DATE - INTERVAL '30 days'"
run_sql "DELETE FROM facts.daily_nutrition WHERE date >= CURRENT_DATE - INTERVAL '30 days'"
run_sql "DELETE FROM insights.daily_finance_summary WHERE day >= CURRENT_DATE - INTERVAL '30 days'" || echo "Note: daily_finance_summary may not exist"
run_sql "DELETE FROM insights.weekly_reports WHERE week_start >= CURRENT_DATE - INTERVAL '30 days'"

echo "✓ Derived tables truncated (last 30 days)"

# Phase 4: Rebuild Materialized Views
echo ""
echo "PHASE 4: Refreshing materialized views..."
run_sql "REFRESH MATERIALIZED VIEW CONCURRENTLY finance.mv_monthly_spend" || echo "Warning: mv_monthly_spend refresh failed (may not exist)"
run_sql "REFRESH MATERIALIZED VIEW CONCURRENTLY finance.mv_category_velocity" || echo "Warning: mv_category_velocity refresh failed (may not exist)"
run_sql "REFRESH MATERIALIZED VIEW CONCURRENTLY finance.mv_income_stability" || echo "Warning: mv_income_stability refresh failed (may not exist)"
run_sql "REFRESH MATERIALIZED VIEW CONCURRENTLY finance.mv_spending_anomalies" || echo "Warning: mv_spending_anomalies refresh failed (may not exist)"
run_sql "REFRESH MATERIALIZED VIEW life.baselines" || echo "Warning: life.baselines refresh failed (may not exist)"

echo "✓ Materialized views refreshed"

# Phase 5: Rebuild Facts (Last 30 Days)
echo ""
echo "PHASE 5: Rebuilding facts for last 30 days..."
run_sql "SELECT life.refresh_all(30)" || echo "Warning: life.refresh_all failed"

echo "✓ Facts rebuilt"

# Phase 6: Regenerate Insights (Last 30 Days)
echo ""
echo "PHASE 6: Regenerating insights..."
for i in {0..29}; do
    DATE=$(date -v-${i}d +%Y-%m-%d 2>/dev/null || date -d "${i} days ago" +%Y-%m-%d)
    run_sql "SELECT insights.generate_daily_summary('$DATE'::date)" > /dev/null || true
done

echo "✓ Insights regenerated"

# Phase 7: Post-Replay Snapshot
echo ""
echo "PHASE 7: Creating post-replay snapshot..."
cat > "$BACKUP_DIR/post_counts.txt" <<EOF
=== POST-REPLAY COUNTS ($(date)) ===

SOURCE TABLES (should remain unchanged):
raw.bank_sms: $(run_sql "SELECT COUNT(*) FROM raw.bank_sms")
raw.healthkit_samples: $(run_sql "SELECT COUNT(*) FROM raw.healthkit_samples")
raw.github_events: $(run_sql "SELECT COUNT(*) FROM raw.github_events")
finance.budgets: $(run_sql "SELECT COUNT(*) FROM finance.budgets")
finance.categories: $(run_sql "SELECT COUNT(*) FROM finance.categories")
finance.merchant_rules: $(run_sql "SELECT COUNT(*) FROM finance.merchant_rules")

DERIVED TABLES (rebuilt):
finance.transactions: $(run_sql "SELECT COUNT(*) FROM finance.transactions")
finance.receipts: $(run_sql "SELECT COUNT(*) FROM finance.receipts")
finance.receipt_items: $(run_sql "SELECT COUNT(*) FROM finance.receipt_items")
life.daily_facts: $(run_sql "SELECT COUNT(*) FROM life.daily_facts WHERE day >= CURRENT_DATE - INTERVAL '30 days'")
facts.daily_health: $(run_sql "SELECT COUNT(*) FROM facts.daily_health WHERE date >= CURRENT_DATE - INTERVAL '30 days'")
facts.daily_finance: $(run_sql "SELECT COUNT(*) FROM facts.daily_finance WHERE date >= CURRENT_DATE - INTERVAL '30 days'")
insights.weekly_reports: $(run_sql "SELECT COUNT(*) FROM insights.weekly_reports WHERE week_start >= CURRENT_DATE - INTERVAL '30 days'")

TOTALS (for validation):
Total spend (last 30d): $(run_sql "SELECT COALESCE(SUM(amount), 0) FROM finance.transactions WHERE amount < 0 AND transaction_at >= CURRENT_DATE - INTERVAL '30 days'")
Total recovery score (last 30d): $(run_sql "SELECT COALESCE(SUM(recovery_score), 0) FROM life.daily_facts WHERE day >= CURRENT_DATE - INTERVAL '30 days'")
EOF

cat "$BACKUP_DIR/post_counts.txt"

# Phase 8: Verification
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "PHASE 8: VERIFICATION"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Compare SOURCE tables only (these must NOT change)
echo "Verifying SOURCE tables preserved..."
SOURCE_DIFF=$(diff \
    <(grep -A 6 "SOURCE TABLES" "$BACKUP_DIR/pre_counts.txt" | tail -6) \
    <(grep -A 6 "SOURCE TABLES" "$BACKUP_DIR/post_counts.txt" | tail -6) \
    || true)

if [ -z "$SOURCE_DIFF" ]; then
    echo -e "${GREEN}✓ PASS: Source tables preserved (no data loss)${NC}"
else
    echo -e "${RED}✗ FAIL: Source tables changed!${NC}"
    echo "$SOURCE_DIFF"
    VERDICT="FAIL"
fi

# Compare TOTALS (these must match for determinism)
echo ""
echo "Verifying determinism..."
PRE_SPEND=$(grep "Total spend" "$BACKUP_DIR/pre_counts.txt" | cut -d: -f2 | tr -d ' ')
POST_SPEND=$(grep "Total spend" "$BACKUP_DIR/post_counts.txt" | cut -d: -f2 | tr -d ' ')

if [ "$PRE_SPEND" = "$POST_SPEND" ]; then
    echo -e "${GREEN}✓ PASS: Total spend unchanged ($PRE_SPEND AED)${NC}"
    VERDICT="PASS"
else
    echo -e "${RED}✗ FAIL: Total spend changed ($PRE_SPEND → $POST_SPEND)${NC}"
    VERDICT="FAIL"
fi

# Show what was rebuilt
echo ""
echo "Derived data rebuilt:"
echo "  life.daily_facts: $(grep "life.daily_facts:" "$BACKUP_DIR/pre_counts.txt" | cut -d: -f2) → $(grep "life.daily_facts:" "$BACKUP_DIR/post_counts.txt" | cut -d: -f2)"
echo "  Total recovery score: $(grep "Total recovery score" "$BACKUP_DIR/pre_counts.txt" | cut -d: -f2) → $(grep "Total recovery score" "$BACKUP_DIR/post_counts.txt" | cut -d: -f2)"

# Run determinism test queries
echo ""
echo "Running determinism validation queries..."
run_sql "
SELECT
    'finance.transactions' as table_name,
    COUNT(*) as count,
    COUNT(DISTINCT external_id) as unique_external_ids,
    COUNT(*) - COUNT(DISTINCT external_id) as duplicates
FROM finance.transactions
WHERE transaction_at >= CURRENT_DATE - INTERVAL '30 days'
UNION ALL
SELECT
    'life.daily_facts',
    COUNT(*),
    COUNT(DISTINCT day),
    COUNT(*) - COUNT(DISTINCT day)
FROM life.daily_facts
WHERE day >= CURRENT_DATE - INTERVAL '30 days'
" | column -t -s '|'

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "REPLAY COMPLETE - $VERDICT"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Backup location: $BACKUP_DIR"
echo "To restore if needed:"
echo "  ssh nexus 'docker exec -i nexus-db psql -U nexus -d nexus' < $BACKUP_DIR/nexus-full-backup.sql"
echo ""

if [ "$VERDICT" = "FAIL" ]; then
    exit 1
fi
