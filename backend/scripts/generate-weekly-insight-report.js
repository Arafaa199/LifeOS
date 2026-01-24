#!/usr/bin/env node

/**
 * Weekly Insight Report Generator
 * Generates weekly summaries with health, finance, and productivity metrics
 *
 * Usage:
 *   node generate-weekly-insight-report.js              # Generate for last complete week
 *   node generate-weekly-insight-report.js 2026-01-13   # Generate for specific week (Monday)
 *   node generate-weekly-insight-report.js --backfill 4 # Backfill last 4 weeks
 */

import pg from 'pg';

const { Pool } = pg;

const pool = new Pool({
  host: process.env.NEXUS_HOST || '100.90.189.16',
  port: parseInt(process.env.NEXUS_PORT || '5432'),
  database: process.env.NEXUS_DB || 'nexus',
  user: process.env.NEXUS_USER || 'nexus',
  password: process.env.NEXUS_PASSWORD,
});

async function generateReport(weekStart) {
  const startTime = Date.now();

  try {
    const result = await pool.query(
      'SELECT insights.generate_weekly_report($1::date) AS report_id',
      [weekStart]
    );

    const duration = Date.now() - startTime;
    const reportId = result.rows[0]?.report_id;

    // Fetch the generated report summary
    const report = await pool.query(
      `SELECT week_start, week_end, avg_recovery, total_spent, total_commits, anomaly_count
       FROM insights.weekly_reports WHERE id = $1`,
      [reportId]
    );

    const row = report.rows[0];
    console.log(`[${new Date().toISOString()}] Generated report for week ${row.week_start} to ${row.week_end}`);
    console.log(`  ID: ${reportId}`);
    console.log(`  Avg Recovery: ${row.avg_recovery || 'N/A'}`);
    console.log(`  Total Spent: ${row.total_spent}`);
    console.log(`  Total Commits: ${row.total_commits}`);
    console.log(`  Anomalies: ${row.anomaly_count}`);
    console.log(`  Duration: ${duration}ms`);

    return { success: true, reportId, duration };
  } catch (err) {
    console.error(`[${new Date().toISOString()}] Error generating report: ${err.message}`);
    return { success: false, error: err.message };
  }
}

async function backfill(weeks) {
  console.log(`[${new Date().toISOString()}] Backfilling last ${weeks} weeks...`);

  const results = { success: 0, failed: 0 };

  for (let i = 1; i <= weeks; i++) {
    // Get Monday of i weeks ago
    const date = new Date();
    date.setDate(date.getDate() - (7 * i) - date.getDay() + 1); // Monday
    const weekStart = date.toISOString().split('T')[0];

    const result = await generateReport(weekStart);
    if (result.success) {
      results.success++;
    } else {
      results.failed++;
    }
  }

  console.log(`\nBackfill complete: ${results.success} success, ${results.failed} failed`);
  return results;
}

async function main() {
  const args = process.argv.slice(2);

  try {
    if (args[0] === '--backfill') {
      const weeks = parseInt(args[1]) || 4;
      await backfill(weeks);
    } else if (args[0]) {
      // Specific week start provided
      await generateReport(args[0]);
    } else {
      // Default to last complete week (pass NULL to let DB calculate)
      await generateReport(null);
    }
  } finally {
    await pool.end();
  }
}

main().catch(console.error);
