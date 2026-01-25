#!/usr/bin/env node

/**
 * Resolve Raw Events - Periodic job to resolve orphan raw_events
 *
 * Runs every 5 minutes via launchd to:
 * 1. Link events that have matching transactions
 * 2. Mark ignored events (OTP, promo, etc.)
 * 3. Mark failed events (pending > 15 minutes)
 *
 * Uses the database function finance.resolve_orphan_events()
 */

import pg from 'pg';

const { Pool } = pg;

// Nexus database connection
const nexusPool = new Pool({
  host: process.env.NEXUS_HOST || '100.90.189.16',
  port: parseInt(process.env.NEXUS_PORT || '5432'),
  database: process.env.NEXUS_DB || 'nexus',
  user: process.env.NEXUS_USER || 'nexus',
  password: process.env.NEXUS_PASSWORD,
});

/**
 * Resolve orphan events using the database function
 */
async function resolveOrphanEvents() {
  const startTime = Date.now();
  const timestamp = new Date().toISOString();

  console.log(`[${timestamp}] Starting raw_events resolution...`);

  try {
    // Call the database function
    const result = await nexusPool.query(`
      SELECT * FROM finance.resolve_orphan_events()
    `);

    const stats = result.rows[0] || { resolved_linked: 0, resolved_ignored: 0, resolved_failed: 0 };

    const duration = ((Date.now() - startTime) / 1000).toFixed(2);

    if (stats.resolved_linked > 0 || stats.resolved_ignored > 0 || stats.resolved_failed > 0) {
      console.log(`[${timestamp}] Resolution complete in ${duration}s:`);
      console.log(`  Linked to transactions: ${stats.resolved_linked}`);
      console.log(`  Marked as ignored: ${stats.resolved_ignored}`);
      console.log(`  Marked as failed: ${stats.resolved_failed}`);
    } else {
      console.log(`[${timestamp}] No pending events to resolve (${duration}s)`);
    }

    // Also print health summary
    const health = await nexusPool.query(`
      SELECT * FROM finance.v_raw_events_health
    `);

    if (health.rows.length > 0) {
      console.log(`\n  Health summary:`);
      for (const row of health.rows) {
        console.log(`    ${row.resolution_status}: ${row.count} (oldest: ${row.oldest?.toISOString()?.split('T')[0] || 'N/A'})`);
      }
    }

    return stats;
  } catch (err) {
    console.error(`[${timestamp}] Error resolving events: ${err.message}`);
    throw err;
  }
}

/**
 * Check for stale pending events (alerts)
 */
async function checkStaleEvents() {
  const result = await nexusPool.query(`
    SELECT COUNT(*) as count,
           MIN(created_at) as oldest
    FROM finance.raw_events
    WHERE resolution_status = 'pending'
      AND created_at < NOW() - INTERVAL '1 hour'
  `);

  const stale = result.rows[0];
  if (stale && stale.count > 0) {
    console.log(`\n⚠️  WARNING: ${stale.count} events pending > 1 hour (oldest: ${stale.oldest?.toISOString()})`);
    console.log('   This may indicate a problem with the SMS importer or transaction creation.');
  }

  return stale;
}

// Main execution
async function main() {
  try {
    await resolveOrphanEvents();
    await checkStaleEvents();
  } finally {
    await nexusPool.end();
  }
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
