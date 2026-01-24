#!/usr/bin/env node

/**
 * SMS Backfill Script
 *
 * Backfills transactions from a copy of chat.db
 * Usage: node backfill-sms.js [path-to-chat.db] [days-back]
 *
 * Example:
 *   node backfill-sms.js ~/tmp/lifeos_sms/chat.db 365
 */

import Database from 'better-sqlite3';
import pg from 'pg';
import { existsSync } from 'fs';
import { SMSClassifier } from './sms-classifier.js';

const { Pool } = pg;

// Parse arguments
const dbPath = process.argv[2] || process.env.MESSAGES_DB;
const daysBack = parseInt(process.argv[3]) || 365;

if (!dbPath) {
  console.error('Usage: node backfill-sms.js <path-to-chat.db> [days-back]');
  console.error('Example: node backfill-sms.js ~/tmp/lifeos_sms/chat.db 365');
  process.exit(1);
}

if (!existsSync(dbPath)) {
  console.error(`Database not found: ${dbPath}`);
  process.exit(1);
}

// Nexus database connection
const nexusPool = new Pool({
  host: process.env.NEXUS_HOST || '100.90.189.16',
  port: parseInt(process.env.NEXUS_PORT || '5432'),
  database: process.env.NEXUS_DB || 'nexus',
  user: process.env.NEXUS_USER || 'nexus',
  password: process.env.NEXUS_PASSWORD,
});

// Account mapping by sender
const ACCOUNT_MAP = {
  'alrajhibank': { account_id: 1, default_currency: 'SAR' },
  'emiratesnbd': { account_id: 2, default_currency: 'AED' },
  'jkb': { account_id: 3, default_currency: 'JOD' },
};

function cleanMerchantName(name) {
  if (!name) return null;
  return name.replace(/\s+/g, ' ').replace(/[,.]$/, '').trim().substring(0, 100);
}

function generateExternalId(messageRowId) {
  return `sms:${messageRowId}`;
}

function intentToType(intent, patternName) {
  switch (intent) {
    case 'income':
      if (patternName?.includes('salary')) return 'Salary';
      if (patternName?.includes('transfer')) return 'Transfer In';
      if (patternName?.includes('deposit')) return 'Deposit';
      return 'Income';
    case 'expense':
      if (patternName?.includes('atm')) return 'ATM';
      if (patternName?.includes('fee')) return 'Fee';
      if (patternName?.includes('ecommerce')) return 'E-commerce';
      return 'Purchase';
    case 'transfer':
      return 'Transfer';
    case 'refund':
      return 'Refund';
    default:
      return 'Unknown';
  }
}

async function backfill() {
  const startTime = Date.now();
  console.log(`[${new Date().toISOString()}] Starting SMS backfill from ${dbPath} (last ${daysBack} days)...`);

  // Initialize classifier
  const classifier = new SMSClassifier();
  const supportedSenders = classifier.getSupportedSenders();
  const senderList = supportedSenders.map(s => `'${s}'`).join(',');

  const messagesDb = new Database(dbPath, { readonly: true });

  const messages = messagesDb.prepare(`
    SELECT
      m.ROWID as rowid,
      h.id as sender,
      m.text,
      datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime') as msg_datetime,
      date(m.date/1000000000 + 978307200, 'unixepoch', 'localtime') as msg_date
    FROM message m
    JOIN handle h ON m.handle_id = h.ROWID
    WHERE LOWER(h.id) IN (${senderList})
      AND m.text IS NOT NULL
      AND length(m.text) > 20
      AND m.date/1000000000 + 978307200 > unixepoch('now', '-${daysBack} days')
    ORDER BY m.date ASC
  `).all();

  console.log(`Found ${messages.length} messages from tracked senders`);

  // Stats
  const stats = {
    total: messages.length,
    imported: 0,
    duplicates: 0,
    excluded: 0,
    declined: 0,
    no_match: 0,
    no_account: 0,
    errors: 0,
    by_intent: { income: 0, expense: 0, transfer: 0, refund: 0 },
    by_sender: {},
  };

  for (const msg of messages) {
    try {
      const senderLower = msg.sender.toLowerCase();

      // Classify message
      const result = classifier.classify(msg.sender, msg.text, msg.msg_date);

      if (!result.matched) {
        if (result.excluded) {
          stats.excluded++;
        } else {
          stats.no_match++;
        }
        continue;
      }

      // Skip declined transactions
      if (result.intent === 'declined' || result.never_create_transaction) {
        stats.declined++;
        continue;
      }

      // Get account info
      const account = ACCOUNT_MAP[senderLower];
      if (!account || !account.account_id) {
        stats.no_account++;
        continue;
      }

      const externalId = generateExternalId(msg.rowid);
      const currency = result.currency || account.default_currency;
      const txType = intentToType(result.intent, result.pattern_name);

      // Insert transaction
      const insertResult = await nexusPool.query(`
        INSERT INTO finance.transactions
          (external_id, account_id, date, merchant_name, merchant_name_clean,
           amount, currency, category, raw_data)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        ON CONFLICT (external_id) DO NOTHING
        RETURNING id
      `, [
        externalId,
        account.account_id,
        msg.msg_date,
        result.merchant,
        cleanMerchantName(result.merchant),
        result.amount,
        currency,
        result.category || txType,
        JSON.stringify({
          sender: msg.sender,
          pattern: result.pattern_name,
          intent: result.intent,
          entities: result.entities,
          original_text: msg.text,
          backfill: true,
          backfill_date: new Date().toISOString(),
        }),
      ]);

      if (insertResult.rowCount > 0) {
        const txId = insertResult.rows[0].id;

        // Apply merchant rules
        await nexusPool.query(`
          UPDATE finance.transactions t
          SET
            category = COALESCE(r.category, t.category),
            subcategory = COALESCE(r.subcategory, t.subcategory),
            is_grocery = COALESCE(r.is_grocery, t.is_grocery),
            is_restaurant = COALESCE(r.is_restaurant, t.is_restaurant),
            is_food_related = COALESCE(r.is_food_related, t.is_food_related),
            store_name = COALESCE(r.store_name, t.store_name),
            match_rule_id = r.id
          FROM (
            SELECT * FROM finance.merchant_rules
            WHERE UPPER($2) LIKE UPPER(merchant_pattern)
            ORDER BY priority DESC
            LIMIT 1
          ) r
          WHERE t.id = $1
        `, [txId, result.merchant || '']);

        stats.imported++;
        stats.by_intent[result.intent]++;
        stats.by_sender[senderLower] = (stats.by_sender[senderLower] || 0) + 1;
      } else {
        stats.duplicates++;
      }
    } catch (err) {
      stats.errors++;
      console.error(`Error processing message ${msg.rowid}: ${err.message}`);
    }
  }

  messagesDb.close();
  await nexusPool.end();

  // Summary
  const duration = ((Date.now() - startTime) / 1000).toFixed(1);
  console.log(`\nBackfill complete in ${duration}s:`);
  console.log(`  New: ${stats.imported}`);
  console.log(`  Duplicates: ${stats.duplicates}`);
  console.log(`  Excluded (OTP/promo): ${stats.excluded}`);
  console.log(`  Declined: ${stats.declined}`);
  console.log(`  No match: ${stats.no_match}`);
  console.log(`  Errors: ${stats.errors}`);
  console.log(`\nBy sender:`);
  for (const [sender, count] of Object.entries(stats.by_sender)) {
    console.log(`  ${sender}: ${count}`);
  }
  console.log(`\nBy intent:`);
  for (const [intent, count] of Object.entries(stats.by_intent)) {
    if (count > 0) console.log(`  ${intent}: ${count}`);
  }

  return stats;
}

backfill().catch(console.error);
