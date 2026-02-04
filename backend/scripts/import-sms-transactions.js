#!/usr/bin/env node

/**
 * SMS Transaction Importer for Nexus (v2)
 *
 * Uses YAML-based regex classifier for deterministic pattern matching.
 * Routes messages by intent: expense/income/transfer/refund → finance.transactions
 *
 * Idempotency: sms:<message_rowid>
 */

import Database from 'better-sqlite3';
import pg from 'pg';
import { homedir } from 'os';
import { existsSync } from 'fs';
import { SMSClassifier } from './sms-classifier.js';

const { Pool } = pg;

// Database paths
const MESSAGES_DB = process.env.MESSAGES_DB || `${homedir()}/Library/Messages/chat.db`;

// Nexus database connection
const nexusPool = new Pool({
  host: process.env.NEXUS_HOST || '10.0.0.11',
  port: parseInt(process.env.NEXUS_PORT || '5432'),
  database: process.env.NEXUS_DB || 'nexus',
  user: process.env.NEXUS_USER || 'nexus',
  password: process.env.NEXUS_PASSWORD,
  max: 3,
  idleTimeoutMillis: 10000,
  connectionTimeoutMillis: 5000,
});

// Account mapping by sender
const ACCOUNT_MAP = {
  'alrajhibank': { account_id: 1, default_currency: 'SAR' },
  'emiratesnbd': { account_id: 2, default_currency: 'AED' },
  'jkb': { account_id: 3, default_currency: 'JOD' },
  'careem': { account_id: null, default_currency: 'AED' }, // Wallet refund, no bank account
  'amazon': { account_id: null, default_currency: 'SAR' }, // Refund notification only
  'tabby': { account_id: null, default_currency: 'AED' },  // Tabby Card spending
  'ad-tabby': { account_id: null, default_currency: 'AED' },
  'tabby-ad': { account_id: null, default_currency: 'AED' },
  'tasheel fin': { account_id: null, default_currency: 'SAR' },
};

// BNPL providers (separate handling)
const BNPL_PROVIDERS = {
  'tabby': { installments: 4, interval_days: 14 },
  'tabby-ad': { installments: 4, interval_days: 14 },
  'ad-tabby': { installments: 4, interval_days: 14 },
};

/**
 * Extract plain text from NSAttributedString blob (attributedBody column).
 * Modern iOS stores SMS body in attributedBody instead of text column.
 * The blob is NSKeyedArchiver-encoded. The plain text follows a '+' (0x2B) marker
 * with a variable-length prefix (BER-style encoding).
 */
function extractTextFromAttributedBody(buffer) {
  if (!buffer || buffer.length === 0) return null;

  // Method 1: Find text after the '+' marker (0x01 0x2B <length> <text>)
  // NSKeyedArchiver uses BER-style length encoding:
  //   - 0x00-0x7F: single byte length
  //   - 0x81: length in next 1 byte
  //   - 0x82: length in next 2 bytes (big-endian)
  for (let i = 0; i < buffer.length - 4; i++) {
    if (buffer[i] === 0x01 && buffer[i + 1] === 0x2B) {
      let textLen, textStart;
      const lenByte = buffer[i + 2];

      if (lenByte < 0x80) {
        // Simple single-byte length
        textLen = lenByte;
        textStart = i + 3;
      } else if (lenByte === 0x81) {
        // Length in next 1 byte
        textLen = buffer[i + 3];
        textStart = i + 4;
      } else if (lenByte === 0x82) {
        // Length in next 2 bytes (big-endian)
        textLen = (buffer[i + 3] << 8) | buffer[i + 4];
        textStart = i + 5;
      } else {
        // Unknown encoding, skip
        continue;
      }

      // Skip any null bytes before the actual text
      while (textStart < buffer.length && buffer[textStart] === 0x00) {
        textStart++;
        textLen--;
      }

      if (textLen > 0 && textStart + textLen <= buffer.length) {
        const text = buffer.slice(textStart, textStart + textLen).toString('utf-8');
        const cleaned = cleanExtractedText(text);
        if (cleaned && cleaned.length > 10) return cleaned;
      }
    }
  }

  // Method 2: Fallback — find longest printable ASCII segment
  const str = buffer.toString('latin1');
  const segments = str.match(/[\x20-\x7e\n\r\t]{15,}/g);
  if (segments && segments.length > 0) {
    const best = segments.reduce((a, b) => a.length >= b.length ? a : b);
    return best.trim();
  }

  return null;
}

function cleanExtractedText(text) {
  if (!text) return null;
  // Strip leading/trailing non-printable characters and control chars
  // Keep Arabic (0600-06FF), Latin, digits, punctuation, whitespace
  return text.replace(/^[^\x20-\x7e\u0600-\u06FF\u0750-\u077F]+/, '')
             .replace(/[^\x20-\x7e\u0600-\u06FF\u0750-\u077F]+$/, '')
             .trim();
}

/**
 * Get message body from either text column or attributedBody blob.
 */
function getMessageBody(msg) {
  if (msg.text && msg.text.length > 10) return msg.text;
  if (msg.attributedBody) return extractTextFromAttributedBody(msg.attributedBody);
  return null;
}

/**
 * Clean merchant name for storage
 */
function cleanMerchantName(name) {
  if (!name) return null;
  return name
    .replace(/\s+/g, ' ')
    .replace(/[,.]$/, '')
    .trim()
    .substring(0, 100);
}

/**
 * Generate external_id for idempotency
 */
function generateExternalId(messageRowId) {
  return `sms:${messageRowId}`;
}

/**
 * Map intent to transaction type string
 */
function intentToType(intent, patternName) {
  switch (intent) {
    case 'income':
      if (patternName?.includes('salary')) return 'Salary';
      if (patternName?.includes('transfer')) return 'Transfer In';
      if (patternName?.includes('deposit')) return 'Deposit';
      if (patternName?.includes('credit')) return 'Credit';
      return 'Income';
    case 'expense':
      if (patternName?.includes('atm')) return 'ATM';
      if (patternName?.includes('fee')) return 'Fee';
      if (patternName?.includes('credit_card_payment')) return 'CC Payment';
      if (patternName?.includes('ecommerce')) return 'E-commerce';
      if (patternName?.includes('pos')) return 'Purchase';
      return 'Purchase';
    case 'transfer':
      return 'Transfer';
    case 'refund':
      return 'Refund';
    default:
      return 'Unknown';
  }
}

/**
 * Find an unlinked transaction from the same sender with opposite subtype
 * for FX pairing (e.g. TASHEEL confirmed↔notification).
 */
async function findPairCandidate(nexusPool, { sender, merchantClean, transactionAt, lookingForSuffix }) {
  const result = await nexusPool.query(`
    SELECT id, amount, currency, raw_data
    FROM finance.transactions
    WHERE raw_data->>'sender' = $1
      AND LOWER(merchant_name_clean) = LOWER($2)
      AND raw_data->>'pattern' LIKE $3
      AND paired_transaction_id IS NULL
      AND pairing_role IS NULL
      AND ABS(EXTRACT(EPOCH FROM (transaction_at - $4::timestamptz))) < 21600
    ORDER BY ABS(EXTRACT(EPOCH FROM (transaction_at - $4::timestamptz))) ASC
    LIMIT 1
  `, [sender, merchantClean, `%${lookingForSuffix}`, transactionAt]);
  return result.rows[0] || null;
}

/**
 * Link two transactions as an FX pair.
 * confirmedId = primary (ledger), notificationId = fx_metadata
 */
async function linkFxPair(nexusPool, confirmedId, notificationId, notificationAmount, notificationCurrency) {
  await nexusPool.query(`
    UPDATE finance.transactions
    SET paired_transaction_id = $1, pairing_role = 'fx_metadata'
    WHERE id = $2
  `, [confirmedId, notificationId]);

  await nexusPool.query(`
    UPDATE finance.transactions
    SET pairing_role = 'primary',
        raw_data = raw_data || jsonb_build_object(
          'fx_amount', $2::text,
          'fx_currency', $3,
          'fx_paired_id', $4
        )
    WHERE id = $1
  `, [confirmedId, notificationAmount, notificationCurrency, notificationId]);
}

/**
 * Import transactions from SMS
 */
async function importTransactions(daysBack = 365, verbose = false) {
  const startTime = Date.now();
  console.log(`[${new Date().toISOString()}] Starting SMS import (last ${daysBack} days)...`);

  if (!existsSync(MESSAGES_DB)) {
    console.error('Messages database not found:', MESSAGES_DB);
    process.exit(1);
  }

  // Initialize classifier
  const classifier = new SMSClassifier();
  const supportedSenders = classifier.getSupportedSenders();
  const bnplSenders = Object.keys(BNPL_PROVIDERS);

  // Build sender list for SQL query
  const allSenders = [...new Set([...supportedSenders, ...bnplSenders])];
  const senderList = allSenders.map(s => `'${s}'`).join(',');
  // Also include capitalized versions
  const capitalizedSenders = allSenders.map(s => `'${s.charAt(0).toUpperCase() + s.slice(1)}'`).join(',');
  const fullSenderList = `${senderList},${capitalizedSenders}`;

  const messagesDb = new Database(MESSAGES_DB, { readonly: true });

  const messages = messagesDb.prepare(`
    SELECT
      m.ROWID as rowid,
      h.id as sender,
      m.text,
      m.attributedBody,
      datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime') as msg_datetime,
      date(m.date/1000000000 + 978307200, 'unixepoch', 'localtime') as msg_date
    FROM message m
    JOIN handle h ON m.handle_id = h.ROWID
    WHERE LOWER(h.id) IN (${senderList})
      AND (m.text IS NOT NULL OR m.attributedBody IS NOT NULL)
      AND m.date/1000000000 + 978307200 > unixepoch('now', '-${daysBack} days')
    ORDER BY m.date DESC
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
  };

  for (const msg of messages) {
    try {
      const senderLower = msg.sender.toLowerCase();

      // Skip pure BNPL senders (handled by importBNPLPurchases)
      // Tabby is excluded: spending messages go through main pipeline,
      // BNPL confirmations are skipped via never_create_transaction flag
      if (bnplSenders.includes(senderLower) && !ACCOUNT_MAP[senderLower]) {
        continue;
      }

      // Extract message body (text column or attributedBody blob)
      const body = getMessageBody(msg);
      if (!body || body.length < 15) {
        stats.no_match++;
        continue;
      }

      // Classify message
      const result = classifier.classify(msg.sender, body, msg.msg_date);

      if (!result.matched) {
        if (result.excluded) {
          stats.excluded++;
          if (verbose) console.log(`  Excluded: ${result.exclusion_reason}`);
        } else {
          stats.no_match++;
          if (verbose) console.log(`  No match: ${body.substring(0, 50)}...`);
        }
        continue;
      }

      // Skip declined/ignored transactions (no financial impact)
      if (result.intent === 'declined' || result.intent === 'ignore' || result.never_create_transaction) {
        stats.declined++;
        if (verbose) console.log(`  Skipped (${result.intent}): ${result.pattern_name}`);
        continue;
      }

      // Get account info
      const account = ACCOUNT_MAP[senderLower];
      if (!account) {
        stats.no_account++;
        if (verbose) console.log(`  No account mapping for sender: ${msg.sender}`);
        continue;
      }

      const externalId = generateExternalId(msg.rowid);
      const currency = result.currency || account.default_currency;
      const txType = intentToType(result.intent, result.pattern_name);

      // Insert transaction
      // Use msg_datetime for transaction_at (actual SMS timestamp)
      // date column is derived from transaction_at via finance.to_business_date()
      const insertResult = await nexusPool.query(`
        INSERT INTO finance.transactions
          (external_id, account_id, transaction_at, date, merchant_name, merchant_name_clean,
           amount, currency, category, source, raw_data)
        VALUES ($1, $2, $3::timestamptz, finance.to_business_date($3::timestamptz), $4, $5, $6, $7, $8, $9, $10)
        ON CONFLICT (external_id) DO NOTHING
        RETURNING id
      `, [
        externalId,
        account.account_id,
        msg.msg_datetime,  // Use full datetime, not just date
        result.merchant,
        cleanMerchantName(result.merchant),
        result.amount,
        currency,
        result.category || 'Uncategorized',
        'sms',
        JSON.stringify({
          sender: msg.sender,
          pattern: result.pattern_name,
          intent: result.intent,
          subtype: result.subtype || undefined,
          entities: result.entities,
          confidence: result.confidence,
          original_text: body,
        }),
      ]);

      if (insertResult.rowCount > 0) {
        const txId = insertResult.rows[0].id;
        let markedFxMetadata = false;

        // FX pairing: if this row has a subtype, try to find its pair
        if (result.subtype === 'purchase_notification') {
          const pair = await findPairCandidate(nexusPool, {
            sender: msg.sender,
            merchantClean: cleanMerchantName(result.merchant),
            transactionAt: msg.msg_datetime,
            lookingForSuffix: '_confirmed',
          });
          if (pair) {
            await linkFxPair(nexusPool, pair.id, txId, Math.abs(result.amount), currency);
            markedFxMetadata = true;
            if (verbose) console.log(`  ⚡ Paired notification ${txId} → confirmed ${pair.id}`);
          }
        } else if (result.subtype === 'purchase_confirmed') {
          const pair = await findPairCandidate(nexusPool, {
            sender: msg.sender,
            merchantClean: cleanMerchantName(result.merchant),
            transactionAt: msg.msg_datetime,
            lookingForSuffix: '_notification',
          });
          if (pair) {
            await linkFxPair(nexusPool, txId, pair.id, Math.abs(pair.amount), pair.currency);
            markedFxMetadata = false; // this row is the primary
            if (verbose) console.log(`  ⚡ Paired confirmed ${txId} ← notification ${pair.id}`);
          }
        }

        // Apply merchant rules for categorization (skip for fx_metadata)
        if (!markedFxMetadata) {
          await nexusPool.query(`
            UPDATE finance.transactions t
            SET
              category = COALESCE(r.category, t.category),
              subcategory = COALESCE(r.subcategory, t.subcategory),
              is_grocery = COALESCE(r.is_grocery, t.is_grocery),
              is_restaurant = COALESCE(r.is_restaurant, t.is_restaurant),
              is_food_related = COALESCE(r.is_food_related, t.is_food_related),
              store_name = COALESCE(r.store_name, t.store_name),
              match_rule_id = r.id,
              match_reason = 'rule:' || r.id,
              match_confidence = r.confidence
            FROM (
              SELECT * FROM finance.merchant_rules
              WHERE UPPER($2) LIKE UPPER(merchant_pattern)
              ORDER BY priority DESC
              LIMIT 1
            ) r
            WHERE t.id = $1
          `, [txId, result.merchant || '']);
        }

        stats.imported++;
        stats.by_intent[result.intent]++;

        if (verbose) {
          console.log(`  ✓ ${result.pattern_name}: ${currency} ${result.amount} at ${result.merchant || 'N/A'}${markedFxMetadata ? ' [fx_metadata]' : ''}`);
        }
      } else {
        stats.duplicates++;
      }
    } catch (err) {
      stats.errors++;
      console.error(`Error processing message ${msg.rowid}: ${err.message}`);
    }
  }

  messagesDb.close();

  // Summary
  const duration = ((Date.now() - startTime) / 1000).toFixed(1);
  console.log(`\nImport complete in ${duration}s:`);
  console.log(`  New: ${stats.imported}`);
  console.log(`  Duplicates: ${stats.duplicates}`);
  console.log(`  Excluded (OTP/promo): ${stats.excluded}`);
  console.log(`  Declined: ${stats.declined}`);
  console.log(`  No match: ${stats.no_match}`);
  console.log(`  No account: ${stats.no_account}`);
  console.log(`  Errors: ${stats.errors}`);
  console.log(`\nBy intent:`);
  for (const [intent, count] of Object.entries(stats.by_intent)) {
    if (count > 0) console.log(`  ${intent}: ${count}`);
  }

  return stats;
}

/**
 * Import BNPL purchases (Tabby, Tamara, etc.)
 */
async function importBNPLPurchases(daysBack = 365) {
  console.log(`\n[${new Date().toISOString()}] Processing BNPL messages...`);

  if (!existsSync(MESSAGES_DB)) return;

  const messagesDb = new Database(MESSAGES_DB, { readonly: true });
  const bnplSenders = Object.keys(BNPL_PROVIDERS).map(s => `'${s}'`).join(',');
  const capitalizedBnpl = Object.keys(BNPL_PROVIDERS).map(s => `'${s.charAt(0).toUpperCase() + s.slice(1)}'`).join(',');

  if (bnplSenders === "''") {
    messagesDb.close();
    return;
  }

  const messages = messagesDb.prepare(`
    SELECT
      m.ROWID as rowid,
      h.id as sender,
      m.text,
      m.attributedBody,
      date(m.date/1000000000 + 978307200, 'unixepoch', 'localtime') as msg_date
    FROM message m
    JOIN handle h ON m.handle_id = h.ROWID
    WHERE LOWER(h.id) IN (${bnplSenders})
      AND (m.text IS NOT NULL OR m.attributedBody IS NOT NULL)
      AND m.date/1000000000 + 978307200 > unixepoch('now', '-${daysBack} days')
    ORDER BY m.date DESC
  `).all();

  console.log(`Found ${messages.length} BNPL messages`);

  let created = 0;
  let duplicates = 0;

  for (const msg of messages) {
    const senderLower = msg.sender.toLowerCase();
    const provider = BNPL_PROVIDERS[senderLower];
    if (!provider) continue;

    // Extract message body
    const body = getMessageBody(msg);
    if (!body) continue;

    // Only process BNPL confirmation messages
    if (!body.match(/purchase.*confirmed|Order of.*confirmed/i)) continue;

    // Parse Tabby format
    let bnpl = null;

    // Format 1: "Your CURRENCY AMOUNT purchase at MERCHANT is confirmed"
    let match = body.match(/Your\s+([A-Z]{3})\s+([\d,.]+)\s+purchase\s+at\s+(.+?)\s+is\s+confirmed/i);
    if (match) {
      bnpl = {
        currency: match[1],
        total_amount: parseFloat(match[2].replace(/,/g, '')),
        merchant: match[3].trim(),
        purchase_date: msg.msg_date,
      };
    }

    // Format 2: "Order of AMOUNT CURRENCY from MERCHANT is confirmed"
    if (!bnpl) {
      match = body.match(/Order\s+of\s+([\d,.]+)\s+([A-Z]{3})\s+from\s+(.+?)\s+is\s+confirmed/i);
      if (match) {
        bnpl = {
          currency: match[2],
          total_amount: parseFloat(match[1].replace(/,/g, '')),
          merchant: match[3].trim(),
          purchase_date: msg.msg_date,
        };
      }
    }

    if (!bnpl) continue;

    // Calculate installment schedule
    const installmentAmount = (bnpl.total_amount / provider.installments).toFixed(2);
    const purchaseDate = new Date(bnpl.purchase_date);
    const nextDueDate = new Date(purchaseDate);
    nextDueDate.setDate(nextDueDate.getDate() + provider.interval_days);
    const finalDueDate = new Date(purchaseDate);
    finalDueDate.setDate(finalDueDate.getDate() + (provider.interval_days * (provider.installments - 1)));

    // Check for duplicate
    const existsCheck = await nexusPool.query(`
      SELECT id FROM finance.scheduled_payments
      WHERE merchant = $1 AND total_amount = $2 AND purchase_date = $3
      LIMIT 1
    `, [bnpl.merchant, bnpl.total_amount, bnpl.purchase_date]);

    if (existsCheck.rows.length > 0) {
      duplicates++;
      continue;
    }

    // Insert scheduled payment
    await nexusPool.query(`
      INSERT INTO finance.scheduled_payments
        (source, merchant, total_amount, installments_total, installments_paid,
         installment_amount, currency, purchase_date, next_due_date, final_due_date, status)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
    `, [
      senderLower,
      bnpl.merchant,
      bnpl.total_amount,
      provider.installments,
      1, // First payment is immediate
      installmentAmount,
      bnpl.currency,
      bnpl.purchase_date,
      nextDueDate.toISOString().split('T')[0],
      finalDueDate.toISOString().split('T')[0],
      'active',
    ]);

    created++;
    console.log(`  Created: ${bnpl.merchant} - ${bnpl.currency} ${bnpl.total_amount} (${provider.installments}x ${installmentAmount})`);
  }

  messagesDb.close();
  console.log(`BNPL import: ${created} new, ${duplicates} duplicates`);
}

/**
 * Match Tabby payments to scheduled payments
 */
async function matchTabbyPayments() {
  console.log(`\n[${new Date().toISOString()}] Matching Tabby payments...`);

  // Find unlinked TABBY FZ LLC transactions
  const tabbyTx = await nexusPool.query(`
    SELECT id, date, ABS(amount) as amount, currency
    FROM finance.transactions
    WHERE merchant_name_clean ILIKE '%tabby%'
      AND amount < 0
      AND id NOT IN (
        SELECT UNNEST(linked_transaction_ids)
        FROM finance.scheduled_payments
        WHERE linked_transaction_ids IS NOT NULL
      )
    ORDER BY date DESC
  `);

  if (tabbyTx.rows.length === 0) {
    console.log('No unlinked Tabby transactions found');
    return;
  }

  console.log(`Found ${tabbyTx.rows.length} unlinked Tabby transactions`);

  for (const tx of tabbyTx.rows) {
    // Find matching scheduled payment by installment amount (with 1% tolerance)
    const match = await nexusPool.query(`
      SELECT id, merchant, installments_paid, installments_total, installment_amount
      FROM finance.scheduled_payments
      WHERE source = 'tabby'
        AND status = 'active'
        AND currency = $1
        AND ABS(installment_amount - $2) < (installment_amount * 0.01)
        AND installments_paid < installments_total
      ORDER BY next_due_date ASC
      LIMIT 1
    `, [tx.currency, tx.amount]);

    if (match.rows.length > 0) {
      const sp = match.rows[0];
      const newPaidCount = sp.installments_paid + 1;
      const newStatus = newPaidCount >= sp.installments_total ? 'completed' : 'active';

      // Calculate next due date
      let nextDue = null;
      if (newStatus === 'active') {
        const nextDate = new Date(tx.date);
        nextDate.setDate(nextDate.getDate() + 14);
        nextDue = nextDate.toISOString().split('T')[0];
      }

      await nexusPool.query(`
        UPDATE finance.scheduled_payments
        SET installments_paid = $1,
            status = $2,
            next_due_date = $3,
            linked_transaction_ids = array_append(COALESCE(linked_transaction_ids, '{}'), $4),
            updated_at = NOW()
        WHERE id = $5
      `, [newPaidCount, newStatus, nextDue, tx.id, sp.id]);

      console.log(`  Matched tx ${tx.id} to "${sp.merchant}" (${newPaidCount}/${sp.installments_total})`);
    }
  }
}

/**
 * Print account summary
 */
async function printAccountSummary() {
  const summary = await nexusPool.query(`
    SELECT
      a.name,
      a.institution,
      COUNT(*) as tx_count,
      SUM(CASE WHEN t.amount < 0 THEN t.amount ELSE 0 END) as spent,
      SUM(CASE WHEN t.amount > 0 THEN t.amount ELSE 0 END) as received
    FROM finance.transactions t
    JOIN finance.accounts a ON t.account_id = a.id
    WHERE t.external_id LIKE 'sms:%'
    GROUP BY a.id, a.name, a.institution
    ORDER BY a.name
  `);

  console.log('\nAccount Summary (SMS transactions):');
  for (const row of summary.rows) {
    console.log(`  ${row.institution}: ${row.tx_count} tx, spent ${Math.abs(row.spent || 0).toFixed(2)}, received ${parseFloat(row.received || 0).toFixed(2)}`);
  }
}

// Main execution
const daysArg = process.argv.find(a => a.startsWith('--days='));
const daysBack = daysArg ? parseInt(daysArg.split('=')[1]) : (parseInt(process.argv[2]) || 365);
const verbose = process.argv.includes('-v') || process.argv.includes('--verbose');

async function runAll() {
  try {
    await importTransactions(daysBack, verbose);
    await importBNPLPurchases(daysBack);
    await matchTabbyPayments();
    await printAccountSummary();
  } finally {
    await nexusPool.end();
  }
}

runAll().catch(console.error);
