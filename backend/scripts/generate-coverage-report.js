#!/usr/bin/env node

/**
 * Generate SMS Coverage Report
 *
 * Creates a markdown report of SMS → Transaction coverage metrics.
 * Output: ops/artifacts/coverage-report-YYYY-MM-DD.md
 */

import pg from 'pg';
import { writeFileSync, mkdirSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const { Pool } = pg;

// Nexus database connection
const nexusPool = new Pool({
  host: process.env.NEXUS_HOST || '100.90.189.16',
  port: parseInt(process.env.NEXUS_PORT || '5432'),
  database: process.env.NEXUS_DB || 'nexus',
  user: process.env.NEXUS_USER || 'nexus',
  password: process.env.NEXUS_PASSWORD,
});

const today = new Date().toISOString().split('T')[0];

/**
 * Get coverage summary
 */
async function getCoverageSummary() {
  const result = await nexusPool.query(`
    SELECT
      COUNT(*) as days_tracked,
      SUM(sms_received) as total_sms,
      SUM(financial_sms) as total_financial_sms,
      SUM(sms_with_tx) as total_captured,
      SUM(missing_count) as total_missing,
      ROUND(SUM(sms_with_tx)::numeric / NULLIF(SUM(financial_sms), 0)::numeric, 3) as capture_rate,
      COUNT(*) FILTER (WHERE status IN ('GAP', 'MINOR_GAP')) as days_with_gaps,
      MIN(date) as earliest_date,
      MAX(date) as latest_date
    FROM finance.v_coverage_gaps
    WHERE status != 'NO_SMS'
  `);
  return result.rows[0] || {};
}

/**
 * Get coverage gaps
 */
async function getCoverageGaps() {
  const result = await nexusPool.query(`
    SELECT
      date::text,
      status,
      financial_sms,
      sms_with_tx,
      missing_count
    FROM finance.v_coverage_gaps
    WHERE status IN ('GAP', 'MINOR_GAP')
    ORDER BY date DESC
    LIMIT 20
  `);
  return result.rows;
}

/**
 * Get raw events resolution stats
 */
async function getResolutionStats() {
  const result = await nexusPool.query(`
    SELECT
      resolution_status,
      COUNT(*) as count,
      MIN(created_at)::date as oldest,
      MAX(created_at)::date as newest
    FROM finance.raw_events
    WHERE created_at >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY resolution_status
    ORDER BY
      CASE resolution_status
        WHEN 'pending' THEN 1
        WHEN 'failed' THEN 2
        WHEN 'ignored' THEN 3
        WHEN 'linked' THEN 4
      END
  `);
  return result.rows;
}

/**
 * Get pattern match statistics
 */
async function getPatternStats() {
  const result = await nexusPool.query(`
    SELECT
      pattern_name,
      COUNT(*) as count,
      COUNT(*) FILTER (WHERE created_transaction = true) as created_tx,
      ROUND(AVG(confidence), 2) as avg_confidence
    FROM raw.sms_classifications
    WHERE received_at >= CURRENT_DATE - INTERVAL '30 days'
      AND canonical_intent IN ('FIN_TXN_APPROVED', 'FIN_TXN_REFUND')
    GROUP BY pattern_name
    ORDER BY count DESC
    LIMIT 15
  `);
  return result.rows;
}

/**
 * Get sender breakdown
 */
async function getSenderStats() {
  const result = await nexusPool.query(`
    SELECT
      sender,
      COUNT(*) as total,
      COUNT(*) FILTER (WHERE canonical_intent IN ('FIN_TXN_APPROVED', 'FIN_TXN_REFUND')) as financial,
      COUNT(*) FILTER (WHERE created_transaction = true) as captured,
      ROUND(
        COUNT(*) FILTER (WHERE created_transaction = true)::numeric /
        NULLIF(COUNT(*) FILTER (WHERE canonical_intent IN ('FIN_TXN_APPROVED', 'FIN_TXN_REFUND')), 0)::numeric,
        2
      ) as capture_rate
    FROM raw.sms_classifications
    WHERE received_at >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY sender
    ORDER BY financial DESC
  `);
  return result.rows;
}

/**
 * Generate markdown report
 */
async function generateReport() {
  console.log(`Generating coverage report for ${today}...`);

  const summary = await getCoverageSummary();
  const gaps = await getCoverageGaps();
  const resolution = await getResolutionStats();
  const patterns = await getPatternStats();
  const senders = await getSenderStats();

  // Calculate health status
  const captureRate = parseFloat(summary.capture_rate || 0);
  let healthStatus = '🔴 CRITICAL';
  let healthDescription = 'Many transactions missing';
  if (captureRate >= 0.99) {
    healthStatus = '🟢 HEALTHY';
    healthDescription = 'All financial SMS captured';
  } else if (captureRate >= 0.95) {
    healthStatus = '🟡 ACCEPTABLE';
    healthDescription = 'Minor gaps detected';
  } else if (captureRate >= 0.90) {
    healthStatus = '🟠 WARNING';
    healthDescription = 'Some transactions missing';
  }

  const report = `# SMS Coverage Report - ${today}

## Executive Summary

| Metric | Value |
|--------|-------|
| Status | ${healthStatus} |
| Assessment | ${healthDescription} |
| Capture Rate | ${(captureRate * 100).toFixed(1)}% |
| Total Financial SMS | ${summary.total_financial_sms || 0} |
| Transactions Created | ${summary.total_captured || 0} |
| Missing | ${summary.total_missing || 0} |
| Days Tracked | ${summary.days_tracked || 0} |
| Period | ${summary.earliest_date || 'N/A'} to ${summary.latest_date || 'N/A'} |

---

## Coverage Gaps

${gaps.length === 0 ? '**No gaps detected in the last 30 days.** ✓' : `
| Date | Status | Financial SMS | Captured | Missing |
|------|--------|---------------|----------|---------|
${gaps.map(g => `| ${g.date} | ${g.status} | ${g.financial_sms} | ${g.sms_with_tx} | ${g.missing_count} |`).join('\n')}
`}

---

## Raw Event Resolution

| Status | Count | Oldest | Newest |
|--------|-------|--------|--------|
${resolution.map(r => `| ${r.resolution_status} | ${r.count} | ${r.oldest || 'N/A'} | ${r.newest || 'N/A'} |`).join('\n') || '| No data | - | - | - |'}

---

## Pattern Performance

| Pattern | Count | Created TX | Avg Confidence |
|---------|-------|------------|----------------|
${patterns.map(p => `| ${p.pattern_name || 'unknown'} | ${p.count} | ${p.created_tx} | ${p.avg_confidence} |`).join('\n') || '| No data | - | - | - |'}

---

## Sender Breakdown

| Sender | Total | Financial | Captured | Rate |
|--------|-------|-----------|----------|------|
${senders.map(s => `| ${s.sender} | ${s.total} | ${s.financial} | ${s.captured} | ${(parseFloat(s.capture_rate || 0) * 100).toFixed(0)}% |`).join('\n') || '| No data | - | - | - | - |'}

---

## Recommendations

${captureRate < 0.99 ? `
### Action Items

1. **Investigate missing transactions** - Check \`raw.sms_missing_transactions\` view
2. **Review pattern matching** - Some SMS may not match expected patterns
3. **Check import logs** - Look for errors in \`~/Cyber/Infrastructure/Nexus-setup/logs/\`
` : `
### All Good ✓

- SMS import is working correctly
- All financial messages are being captured
- No action required
`}

---

*Generated: ${new Date().toISOString()}*
*Report covers last 30 days of SMS data*
`;

  // Write to ops/artifacts
  const opsDir = join(__dirname, '../../ops/artifacts');
  const outputPath = join(opsDir, `coverage-report-${today}.md`);

  try {
    mkdirSync(opsDir, { recursive: true });
  } catch (e) {
    // Directory exists
  }

  writeFileSync(outputPath, report);
  console.log(`\n✓ Report saved to: ${outputPath}`);

  // Also print summary to console
  console.log(`\n${'='.repeat(50)}`);
  console.log(`Coverage Summary - ${today}`);
  console.log(`${'='.repeat(50)}`);
  console.log(`Status: ${healthStatus}`);
  console.log(`Capture Rate: ${(captureRate * 100).toFixed(1)}%`);
  console.log(`Financial SMS: ${summary.total_financial_sms || 0}`);
  console.log(`Captured: ${summary.total_captured || 0}`);
  console.log(`Missing: ${summary.total_missing || 0}`);
  console.log(`Days with gaps: ${summary.days_with_gaps || 0}`);
  console.log(`${'='.repeat(50)}\n`);

  return {
    status: healthStatus,
    captureRate,
    summary,
    gaps,
    outputPath,
  };
}

// Main execution
async function main() {
  try {
    const result = await generateReport();
    process.exit(result.captureRate >= 0.99 ? 0 : 1);
  } finally {
    await nexusPool.end();
  }
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
