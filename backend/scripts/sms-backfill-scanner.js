#!/usr/bin/env node

/**
 * SMS Backfill Scanner
 *
 * Reads historical messages from ~/Library/Messages/chat.db
 * Classifies intent for ALL messages
 * Records classifications in raw.sms_classifications
 * Identifies gaps where financial SMS didn't create transactions
 *
 * Usage:
 *   node sms-backfill-scanner.js [--days N] [--dry-run] [--verbose]
 */

import Database from 'better-sqlite3';
import pg from 'pg';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { SMSClassifierV2 } from './sms-classifier-v2.js';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Config
const CHAT_DB_PATH = join(process.env.HOME, 'Library/Messages/chat.db');
const DAYS_BACK = parseInt(process.argv.find(a => a.startsWith('--days='))?.split('=')[1] || '365');
const DRY_RUN = process.argv.includes('--dry-run');
const VERBOSE = process.argv.includes('--verbose');

// Tracked senders (banks and financial services)
const TRACKED_SENDERS = [
  'emiratesnbd',
  'alrajhibank',
  'enbd',
  'jkb',
  'careem',
  'amazon',
  'apple',
];

// Postgres connection
const pgPool = new pg.Pool({
  host: process.env.NEXUS_HOST || '100.90.189.16',
  port: 5432,
  database: 'nexus',
  user: 'nexus',
  password: process.env.NEXUS_PASSWORD,
});

async function main() {
  console.log('SMS Backfill Scanner');
  console.log('====================');
  console.log(`Days back: ${DAYS_BACK}`);
  console.log(`Dry run: ${DRY_RUN}`);
  console.log(`Verbose: ${VERBOSE}`);
  console.log();

  // Initialize classifier
  const classifier = new SMSClassifierV2();
  console.log('Classifier loaded:', classifier.getStats().version);

  // Open chat.db
  let chatDb;
  try {
    chatDb = new Database(CHAT_DB_PATH, { readonly: true });
    console.log('Opened chat.db successfully');
  } catch (err) {
    console.error(`Failed to open chat.db: ${err.message}`);
    console.error('Ensure Terminal has Full Disk Access in System Preferences');
    process.exit(1);
  }

  // Query messages from tracked senders
  const cutoffDate = new Date();
  cutoffDate.setDate(cutoffDate.getDate() - DAYS_BACK);
  const cutoffTimestamp = (cutoffDate.getTime() / 1000) - 978307200; // Convert to Apple timestamp

  const query = `
    SELECT
      m.ROWID as message_id,
      m.text,
      datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime') as received_at,
      h.id as sender
    FROM message m
    JOIN handle h ON m.handle_id = h.ROWID
    WHERE m.date > ?
      AND m.is_from_me = 0
      AND m.text IS NOT NULL
      AND LENGTH(m.text) > 10
    ORDER BY m.date DESC
  `;

  const messages = chatDb.prepare(query).all(cutoffTimestamp * 1000000000);
  console.log(`Found ${messages.length} messages in date range`);

  // Filter to tracked senders
  const trackedMessages = messages.filter((m) => {
    const senderLower = (m.sender || '').toLowerCase();
    return TRACKED_SENDERS.some((s) => senderLower.includes(s));
  });
  console.log(`${trackedMessages.length} from tracked senders`);

  // Get existing transactions for linking
  const existingTx = new Map();
  if (!DRY_RUN) {
    const txResult = await pgPool.query(`
      SELECT id, external_id
      FROM finance.transactions
      WHERE external_id LIKE 'sms:%'
    `);
    for (const row of txResult.rows) {
      const msgId = row.external_id.replace('sms:', '');
      existingTx.set(msgId, row.id);
    }
    console.log(`Found ${existingTx.size} existing SMS transactions`);
  }

  // Classify all messages
  const stats = {
    total: 0,
    byIntent: {},
    shouldCreateTx: 0,
    didCreateTx: 0,
    missing: 0,
    inserted: 0,
    updated: 0,
    errors: 0,
  };

  console.log('\nClassifying messages...');

  for (const msg of trackedMessages) {
    stats.total++;

    const result = classifier.classify(msg.sender, msg.text, msg.received_at);

    // Track stats
    stats.byIntent[result.canonicalIntent] = (stats.byIntent[result.canonicalIntent] || 0) + 1;

    if (result.shouldCreateTransaction) {
      stats.shouldCreateTx++;

      // Check if transaction exists
      const txId = existingTx.get(String(msg.message_id));
      if (txId) {
        stats.didCreateTx++;
        result.transactionId = txId;
        result.createdTransaction = true;
      } else {
        stats.missing++;
        result.createdTransaction = false;
      }
    }

    if (VERBOSE && result.shouldCreateTransaction && !result.createdTransaction) {
      console.log(`  MISSING: [${msg.sender}] ${msg.text.substring(0, 60)}...`);
      console.log(`    Intent: ${result.canonicalIntent}, Amount: ${result.currency} ${result.amount}`);
    }

    // Insert/update classification record
    if (!DRY_RUN) {
      try {
        await pgPool.query(
          `SELECT raw.classify_and_record_sms($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
          [
            String(msg.message_id),
            msg.sender,
            msg.received_at,
            result.canonicalIntent,
            result.legacyIntent || null,
            result.patternName || null,
            result.confidence || 0,
            result.amountAbs || null,
            result.currency || null,
            result.merchant || null,
          ]
        );

        // Mark if transaction was created
        if (result.createdTransaction && result.transactionId) {
          await pgPool.query(
            `SELECT raw.mark_sms_transaction_created($1, $2)`,
            [String(msg.message_id), result.transactionId]
          );
        }

        stats.inserted++;
      } catch (err) {
        stats.errors++;
        if (VERBOSE) {
          console.error(`  Error recording ${msg.message_id}: ${err.message}`);
        }
      }
    }
  }

  chatDb.close();

  // Print summary
  console.log('\n=== SUMMARY ===');
  console.log(`Total messages scanned: ${stats.total}`);
  console.log(`\nBy Intent:`);
  for (const [intent, count] of Object.entries(stats.byIntent).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${intent}: ${count}`);
  }
  console.log(`\nTransaction Coverage:`);
  console.log(`  Should create TX: ${stats.shouldCreateTx}`);
  console.log(`  Did create TX: ${stats.didCreateTx}`);
  console.log(`  MISSING: ${stats.missing}`);
  console.log(`  Coverage: ${stats.shouldCreateTx > 0 ? ((stats.didCreateTx / stats.shouldCreateTx) * 100).toFixed(1) : 100}%`);

  if (!DRY_RUN) {
    console.log(`\nDatabase:`);
    console.log(`  Classifications recorded: ${stats.inserted}`);
    console.log(`  Errors: ${stats.errors}`);
  }

  // Query coverage view
  if (!DRY_RUN) {
    console.log('\n=== COVERAGE SUMMARY ===');
    const coverage = await pgPool.query('SELECT * FROM raw.sms_coverage_summary');
    if (coverage.rows[0]) {
      const c = coverage.rows[0];
      console.log(`Days tracked: ${c.days_tracked}`);
      console.log(`Total messages: ${c.total_messages}`);
      console.log(`Should have TX: ${c.total_should_have_tx}`);
      console.log(`Did create TX: ${c.total_did_create_tx}`);
      console.log(`Missing: ${c.total_missing}`);
      console.log(`Overall coverage: ${(parseFloat(c.overall_coverage) * 100).toFixed(1)}%`);
      console.log(`Days with gaps: ${c.days_with_gaps}`);
    }
  }

  await pgPool.end();
  console.log('\nDone.');
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
