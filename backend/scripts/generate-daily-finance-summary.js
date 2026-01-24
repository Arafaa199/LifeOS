#!/usr/bin/env node

/**
 * Daily Finance Summary Generator
 * Generates daily finance summaries and stores them in insights.daily_finance_summary
 *
 * Usage:
 *   node generate-daily-finance-summary.js           # Generate for today
 *   node generate-daily-finance-summary.js 2026-01-24  # Generate for specific date
 *   node generate-daily-finance-summary.js --backfill 7  # Backfill last 7 days
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

async function generateSummary(targetDate) {
  const startTime = Date.now();

  try {
    const result = await pool.query(
      'SELECT insights.generate_daily_summary($1::date) AS summary_id',
      [targetDate]
    );

    const duration = Date.now() - startTime;
    const summaryId = result.rows[0]?.summary_id;

    // Fetch the generated summary for display
    const summary = await pool.query(
      `SELECT summary_date, yesterday_spent, mtd_spent, mtd_income, anomaly_count
       FROM insights.daily_finance_summary WHERE id = $1`,
      [summaryId]
    );

    const row = summary.rows[0];
    console.log(`[${new Date().toISOString()}] Generated summary for ${targetDate}`);
    console.log(`  ID: ${summaryId}`);
    console.log(`  Yesterday Spent: ${row.yesterday_spent}`);
    console.log(`  MTD Spent: ${row.mtd_spent}`);
    console.log(`  MTD Income: ${row.mtd_income}`);
    console.log(`  Anomalies: ${row.anomaly_count}`);
    console.log(`  Duration: ${duration}ms`);

    return { success: true, summaryId, duration };
  } catch (err) {
    console.error(`[${new Date().toISOString()}] Error generating summary for ${targetDate}: ${err.message}`);
    return { success: false, error: err.message };
  }
}

async function backfill(days) {
  console.log(`[${new Date().toISOString()}] Backfilling last ${days} days...`);

  const results = { success: 0, failed: 0 };

  for (let i = 0; i < days; i++) {
    const date = new Date();
    date.setDate(date.getDate() - i);
    const dateStr = date.toISOString().split('T')[0];

    const result = await generateSummary(dateStr);
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
      const days = parseInt(args[1]) || 7;
      await backfill(days);
    } else if (args[0]) {
      // Specific date provided
      await generateSummary(args[0]);
    } else {
      // Default to today (Dubai timezone)
      const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dubai' });
      await generateSummary(today);
    }
  } finally {
    await pool.end();
  }
}

main().catch(console.error);
