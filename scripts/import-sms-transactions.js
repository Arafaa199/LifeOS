#!/usr/bin/env node

/**
 * SMS Transaction Importer for Nexus
 * Reads bank SMS messages from macOS Messages app and imports to Nexus
 *
 * To add a new bank:
 * 1. Add sender ID to BANKS config
 * 2. Create a parser function
 * 3. Add account to database: INSERT INTO finance.accounts (name, institution, ...) VALUES (...)
 */

import Database from 'better-sqlite3';
import pg from 'pg';
import { createHash } from 'crypto';
import { homedir } from 'os';
import { existsSync } from 'fs';

const { Pool } = pg;

// ============================================================================
// CONFIGURATION - Edit this section to add new banks
// ============================================================================

const BANKS = {
  // AlRajhi Bank (Saudi Arabia)
  'AlRajhiBank': {
    account_id: 1,
    currency: 'SAR',
    parser: parseAlRajhi,
  },

  // Emirates NBD (UAE)
  'EmiratesNBD': {
    account_id: 2,
    currency: 'AED',
    parser: parseEmiratesNBD,
  },

  // Jordan Kuwait Bank
  'JKB': {
    account_id: 3,
    currency: 'JOD',
    parser: parseJKB,
  },
  'jkb': {
    account_id: 3,
    currency: 'JOD',
    parser: parseJKB,
  },
};

// BNPL providers - these create scheduled_payments, not transactions
const BNPL_PROVIDERS = {
  'Tabby': {
    parser: parseTabbyBNPL,
    installments: 4,
    interval_days: 14, // 2 weeks between payments
  },
  'tabby': {
    parser: parseTabbyBNPL,
    installments: 4,
    interval_days: 14,
  },
  'Tabby-AD': {
    parser: parseTabbyBNPL,
    installments: 4,
    interval_days: 14,
  },
};

// Database paths
const MESSAGES_DB = `${homedir()}/Library/Messages/chat.db`;

// Nexus database connection
const nexusPool = new Pool({
  host: process.env.NEXUS_HOST || '100.90.189.16',
  port: parseInt(process.env.NEXUS_PORT || '5432'),
  database: process.env.NEXUS_DB || 'nexus',
  user: process.env.NEXUS_USER || 'nexus',
  password: process.env.NEXUS_PASSWORD,
});

// ============================================================================
// PARSERS - One function per bank
// Each parser receives (messageText, messageDate) and returns:
// { date, merchant, amount (negative=expense), currency, type } or null
// ============================================================================

function parseAlRajhi(text, msgDate) {
  /**
   * AlRajhi Bank SMS Format:
   * PoS / Online Purchase / Internal Transfer / ATM / Refund
   * By:CARD;TYPE
   * From:ACCOUNT (optional)
   * Amount:CURRENCY AMOUNT
   * At:MERCHANT
   * Date:YY-M-D HH:MM
   */

  const lines = text.split('\n').map(l => l.trim());
  const txType = lines[0];

  // Only process transaction messages
  const validTypes = ['PoS', 'Online Purchase', 'Internal Transfer', 'ATM', 'Refund', 'Salary', 'Credit'];
  if (!validTypes.some(t => txType.includes(t))) {
    return null;
  }

  let amount = null;
  let currency = 'SAR';
  let merchant = null;
  let date = msgDate;

  for (const line of lines) {
    // Amount:SAR 48 or Amount:USD 490.00
    const amountMatch = line.match(/^Amount:\s*([A-Z]{3})\s+([\d,.]+)/i);
    if (amountMatch) {
      currency = amountMatch[1].toUpperCase();
      amount = parseFloat(amountMatch[2].replace(/,/g, ''));
      // Expenses are negative, income is positive
      if (!['Refund', 'Salary', 'Credit'].some(t => txType.includes(t))) {
        amount = -amount;
      }
    }

    // At:MERCHANT
    const merchantMatch = line.match(/^At:\s*(.+)/i);
    if (merchantMatch) {
      merchant = merchantMatch[1].trim();
    }

    // To:NAME (for transfers out)
    const toMatch = line.match(/^To:\s*(.+)/i);
    if (toMatch && !merchant) {
      merchant = `Transfer to ${toMatch[1].trim()}`;
    }

    // From:NAME (for transfers in)
    const fromMatch = line.match(/^From:\s*(.+)/i);
    if (fromMatch && txType.includes('Credit')) {
      merchant = `Transfer from ${fromMatch[1].trim()}`;
    }

    // Date:YY-M-D HH:MM (AlRajhi format: 25-1-31 = Jan 31, 2025)
    const dateMatch = line.match(/^Date:\s*(\d{1,2})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})/);
    if (dateMatch) {
      let [, yy, month, day] = dateMatch;
      // AlRajhi format is YY-M-D (e.g., 25-1-31 = Jan 31, 2025)
      const year = parseInt(yy) < 50 ? 2000 + parseInt(yy) : 1900 + parseInt(yy);
      date = `${year}-${String(parseInt(month)).padStart(2, '0')}-${String(parseInt(day)).padStart(2, '0')}`;
    }
  }

  if (!amount) return null;

  return { date, merchant: merchant || txType, amount, currency, type: txType };
}

function parseEmiratesNBD(text, msgDate) {
  /**
   * Emirates NBD SMS Format (Arabic):
   * Purchase: تمت عملية شراء بقيمة AED X.XX لدى MERCHANT ,CITY
   * ATM: تم سحب مبلغ AED X.XX
   * Deposit: تم إيداع مبلغ AED X.XX
   */

  // Purchase
  const purchaseMatch = text.match(/تمت عملية شراء بقيمة\s+([A-Z]{3})\s+([\d,.]+)\s+لدى\s+([^,]+)/);
  if (purchaseMatch) {
    return {
      date: msgDate,
      merchant: purchaseMatch[3].trim(),
      amount: -parseFloat(purchaseMatch[2].replace(/,/g, '')),
      currency: purchaseMatch[1],
      type: 'Purchase',
    };
  }

  // ATM withdrawal
  const atmMatch = text.match(/تم سحب مبلغ\s+([A-Z]{3})\s+([\d,.]+)/);
  if (atmMatch) {
    return {
      date: msgDate,
      merchant: 'ATM Withdrawal',
      amount: -parseFloat(atmMatch[2].replace(/,/g, '')),
      currency: atmMatch[1],
      type: 'ATM',
    };
  }

  // Deposit
  const depositMatch = text.match(/تم إيداع مبلغ\s+([A-Z]{3})\s+([\d,.]+)/);
  if (depositMatch) {
    return {
      date: msgDate,
      merchant: 'Deposit',
      amount: parseFloat(depositMatch[2].replace(/,/g, '')),
      currency: depositMatch[1],
      type: 'Deposit',
    };
  }

  // Salary credit - Emirates NBD format: تم ايداع الراتب AED 23,500.00 في حسابك
  const salaryMatch = text.match(/تم ايداع الراتب\s+([A-Z]{3})\s+([\d,.]+)/);
  if (salaryMatch) {
    return {
      date: msgDate,
      merchant: 'Salary',
      amount: parseFloat(salaryMatch[2].replace(/,/g, '')),
      currency: salaryMatch[1],
      type: 'Salary',
    };
  }

  // Transfer in (credit) - تم تحويل / received transfer
  const transferInMatch = text.match(/تم تحويل.*?([A-Z]{3})\s+([\d,.]+).*?(?:إلى|الى|to)\s*حسابك/i);
  if (transferInMatch) {
    return {
      date: msgDate,
      merchant: 'Transfer In',
      amount: parseFloat(transferInMatch[2].replace(/,/g, '')),
      currency: transferInMatch[1],
      type: 'Transfer',
    };
  }

  return null;
}

// ============================================================================
// BNPL PARSERS - For Buy Now Pay Later services (Tabby, Tamara, etc.)
// These create scheduled_payments entries, not transactions
// ============================================================================

function parseTabbyBNPL(text, msgDate) {
  /**
   * Tabby SMS Formats:
   * 1. "Your AED 1495.00 purchase at Amazon.ae is confirmed..."
   * 2. "Order of 1554.00 SAR from BodyMasters is confirmed..."
   */

  // Format 1: "Your CURRENCY AMOUNT purchase at MERCHANT is confirmed"
  let match = text.match(/Your\s+([A-Z]{3})\s+([\d,.]+)\s+purchase\s+at\s+(.+?)\s+is\s+confirmed/i);
  if (match) {
    const linkMatch = text.match(/https:\/\/tabby\.ai\/\w+/);
    return {
      currency: match[1],
      total_amount: parseFloat(match[2].replace(/,/g, '')),
      merchant: match[3].trim(),
      order_reference: linkMatch ? linkMatch[0] : null,
      purchase_date: msgDate,
    };
  }

  // Format 2: "Order of AMOUNT CURRENCY from MERCHANT is confirmed"
  match = text.match(/Order\s+of\s+([\d,.]+)\s+([A-Z]{3})\s+from\s+(.+?)\s+is\s+confirmed/i);
  if (match) {
    const linkMatch = text.match(/https:\/\/tabby\.ai\/\w+/);
    return {
      currency: match[2],
      total_amount: parseFloat(match[1].replace(/,/g, '')),
      merchant: match[3].trim(),
      order_reference: linkMatch ? linkMatch[0] : null,
      purchase_date: msgDate,
    };
  }

  return null;
}

function parseJKB(text, msgDate) {
  /**
   * Jordan Kuwait Bank SMS Format:
   * Arabic deposit: تم ايداع مبلغ X في حسابك
   * Arabic fee: تم قيد مبلغ X JOD على حسابكم ... عمولة
   * English withdrawal: You have an approved withdrawal trx for SAR X.XX at MERCHANT
   * English purchase: purchase ... SAR X.XX ... at MERCHANT
   */

  // Arabic deposit
  const depositMatch = text.match(/تم ايداع\s+مبلغ\s+([\d,.]+)\s+في/);
  if (depositMatch) {
    return {
      date: msgDate,
      merchant: 'Deposit',
      amount: parseFloat(depositMatch[1].replace(/,/g, '')),
      currency: 'JOD',
      type: 'Deposit',
    };
  }

  // Arabic fee
  const feeMatch = text.match(/تم قيد مبلغ\s+([\d,.]+)\s+JOD\s+على حسابكم.*?(عمولة|رسوم)/);
  if (feeMatch) {
    return {
      date: msgDate,
      merchant: 'Bank Fee',
      amount: -parseFloat(feeMatch[1].replace(/,/g, '')),
      currency: 'JOD',
      type: 'Fee',
    };
  }

  // English withdrawal
  const withdrawMatch = text.match(/approved withdrawal trx for\s+([A-Z]{3})\s+([\d,.]+).*?at\s+([^,]+)/i);
  if (withdrawMatch) {
    return {
      date: msgDate,
      merchant: withdrawMatch[3].trim(),
      amount: -parseFloat(withdrawMatch[2].replace(/,/g, '')),
      currency: withdrawMatch[1],
      type: 'ATM',
    };
  }

  // English purchase
  const purchaseMatch = text.match(/purchase.*?([A-Z]{3})\s+([\d,.]+).*?at\s+([^,]+)/i);
  if (purchaseMatch) {
    return {
      date: msgDate,
      merchant: purchaseMatch[3].trim(),
      amount: -parseFloat(purchaseMatch[2].replace(/,/g, '')),
      currency: purchaseMatch[1],
      type: 'Purchase',
    };
  }

  return null;
}

// ============================================================================
// TEMPLATE FOR NEW BANKS - Copy and modify this
// ============================================================================

/*
function parseNewBank(text, msgDate) {
  // Example patterns - adjust for your bank's SMS format

  // Purchase pattern
  const purchaseMatch = text.match(/purchase of (\w+) ([\d,.]+) at (.+)/i);
  if (purchaseMatch) {
    return {
      date: msgDate,
      merchant: purchaseMatch[3].trim(),
      amount: -parseFloat(purchaseMatch[2].replace(/,/g, '')),
      currency: purchaseMatch[1],
      type: 'Purchase',
    };
  }

  return null;
}
*/

// ============================================================================
// IMPORT LOGIC - No changes needed below
// ============================================================================

function generateExternalId(sender, date, text) {
  const hash = createHash('md5').update(`${sender}|${date}|${text}`).digest('hex');
  return `sms-${hash.substring(0, 16)}`;
}

function cleanMerchantName(name) {
  if (!name) return null;
  return name
    .replace(/\s+/g, ' ')
    .replace(/[,.]$/, '')
    .trim()
    .substring(0, 100);
}

async function importTransactions(daysBack = 365) {
  const startTime = Date.now();
  console.log(`[${new Date().toISOString()}] Starting SMS import (last ${daysBack} days)...`);

  if (!existsSync(MESSAGES_DB)) {
    console.error('Messages database not found. Are you on macOS with Messages?');
    process.exit(1);
  }

  const messagesDb = new Database(MESSAGES_DB, { readonly: true });
  const senderList = Object.keys(BANKS).map(s => `'${s}'`).join(',');

  const messages = messagesDb.prepare(`
    SELECT
      h.id as sender,
      m.text,
      m.date as raw_date,
      datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime') as msg_date
    FROM message m
    JOIN handle h ON m.handle_id = h.ROWID
    WHERE h.id IN (${senderList})
      AND m.text IS NOT NULL
      AND length(m.text) > 20
      AND m.date/1000000000 + 978307200 > unixepoch('now', '-${daysBack} days')
    ORDER BY m.date DESC
  `).all();

  console.log(`Found ${messages.length} bank messages`);

  let imported = 0;
  let skipped = 0;
  let duplicates = 0;
  let errors = 0;

  for (const msg of messages) {
    try {
      const bank = BANKS[msg.sender];
      if (!bank) {
        skipped++;
        continue;
      }

      const date = msg.msg_date.split(' ')[0];
      const tx = bank.parser(msg.text, date);

      if (!tx) {
        skipped++;
        continue;
      }

      const externalId = generateExternalId(msg.sender, msg.msg_date, msg.text);

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
        bank.account_id,
        tx.date,
        tx.merchant,
        cleanMerchantName(tx.merchant),
        tx.amount,
        tx.currency,
        tx.type,
        JSON.stringify({ sender: msg.sender, original_text: msg.text }),
      ]);

      if (insertResult.rowCount > 0) {
        // Apply merchant rules to categorize the new transaction
        const txId = insertResult.rows[0].id;
        await nexusPool.query(`
          UPDATE finance.transactions t
          SET
            category = COALESCE(r.category, t.category),
            subcategory = COALESCE(r.subcategory, t.subcategory),
            is_grocery = COALESCE(r.is_grocery, t.is_grocery),
            is_restaurant = COALESCE(r.is_restaurant, t.is_restaurant),
            is_food_related = COALESCE(r.is_food_related, t.is_food_related),
            store_name = COALESCE(r.store_name, t.store_name)
          FROM (
            SELECT * FROM finance.merchant_rules
            WHERE UPPER($2) LIKE UPPER(merchant_pattern)
            ORDER BY priority DESC
            LIMIT 1
          ) r
          WHERE t.id = $1
        `, [txId, tx.merchant || '']);
        imported++;
      } else {
        duplicates++;
      }
    } catch (err) {
      errors++;
      console.error(`Error: ${err.message}`);
    }
  }

  messagesDb.close();

  // Summary
  const duration = ((Date.now() - startTime) / 1000).toFixed(1);
  console.log(`\nImport complete in ${duration}s:`);
  console.log(`  New: ${imported}`);
  console.log(`  Duplicates: ${duplicates}`);
  console.log(`  Skipped: ${skipped}`);
  console.log(`  Errors: ${errors}`);

  // Account totals
  const summary = await nexusPool.query(`
    SELECT
      a.name,
      a.institution,
      COUNT(*) as tx_count,
      SUM(CASE WHEN t.amount < 0 THEN t.amount ELSE 0 END) as spent,
      SUM(CASE WHEN t.amount > 0 THEN t.amount ELSE 0 END) as received
    FROM finance.transactions t
    JOIN finance.accounts a ON t.account_id = a.id
    GROUP BY a.id, a.name, a.institution
    ORDER BY a.name
  `);

  console.log('\nAccount Summary:');
  for (const row of summary.rows) {
    console.log(`  ${row.institution}: ${row.tx_count} tx, spent ${Math.abs(row.spent).toFixed(2)}, received ${parseFloat(row.received).toFixed(2)}`);
  }
}

// ============================================================================
// BNPL IMPORT LOGIC - Process Buy Now Pay Later SMS
// ============================================================================

async function importBNPLPurchases(daysBack = 365) {
  console.log(`\n[${new Date().toISOString()}] Processing BNPL messages...`);

  if (!existsSync(MESSAGES_DB)) return;

  const messagesDb = new Database(MESSAGES_DB, { readonly: true });
  const bnplSenders = Object.keys(BNPL_PROVIDERS).map(s => `'${s}'`).join(',');

  if (bnplSenders === '') {
    messagesDb.close();
    return;
  }

  const messages = messagesDb.prepare(`
    SELECT
      h.id as sender,
      m.text,
      datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime') as msg_date
    FROM message m
    JOIN handle h ON m.handle_id = h.ROWID
    WHERE h.id IN (${bnplSenders})
      AND m.text IS NOT NULL
      AND (m.text LIKE '%purchase%confirmed%' OR m.text LIKE '%Order of%confirmed%')
      AND m.date/1000000000 + 978307200 > unixepoch('now', '-${daysBack} days')
    ORDER BY m.date DESC
  `).all();

  console.log(`Found ${messages.length} BNPL messages`);

  let created = 0;
  let duplicates = 0;

  for (const msg of messages) {
    const provider = BNPL_PROVIDERS[msg.sender];
    if (!provider) continue;

    const date = msg.msg_date.split(' ')[0];
    const bnpl = provider.parser(msg.text, date);
    if (!bnpl) continue;

    // Calculate installment schedule
    const installmentAmount = (bnpl.total_amount / provider.installments).toFixed(2);
    const purchaseDate = new Date(bnpl.purchase_date);
    const nextDueDate = new Date(purchaseDate);
    nextDueDate.setDate(nextDueDate.getDate() + provider.interval_days);
    const finalDueDate = new Date(purchaseDate);
    finalDueDate.setDate(finalDueDate.getDate() + (provider.interval_days * (provider.installments - 1)));

    // Check for duplicate by merchant+amount+date combo (order_reference is often generic)
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
         installment_amount, currency, purchase_date, next_due_date, final_due_date,
         order_reference, status)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
    `, [
      msg.sender.toLowerCase(),
      bnpl.merchant,
      bnpl.total_amount,
      provider.installments,
      1, // First payment is immediate
      installmentAmount,
      bnpl.currency,
      bnpl.purchase_date,
      nextDueDate.toISOString().split('T')[0],
      finalDueDate.toISOString().split('T')[0],
      bnpl.order_reference,
      'active',
    ]);

    created++;
    console.log(`  Created: ${bnpl.merchant} - ${bnpl.currency} ${bnpl.total_amount} (${provider.installments}x ${installmentAmount})`);
  }

  messagesDb.close();
  console.log(`BNPL import: ${created} new, ${duplicates} duplicates`);
}

// ============================================================================
// AUTO-MATCH TABBY PAYMENTS - Link TABBY FZ LLC transactions to scheduled_payments
// ============================================================================

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

// Run
const daysBack = parseInt(process.argv[2]) || 365;

async function runAll() {
  try {
    await importTransactions(daysBack);
    await importBNPLPurchases(daysBack);
    await matchTabbyPayments();
  } finally {
    await nexusPool.end();
  }
}

runAll().catch(console.error);
