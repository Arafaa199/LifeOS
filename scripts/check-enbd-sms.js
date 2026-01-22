#!/usr/bin/env node

import Database from 'better-sqlite3';
import { homedir } from 'os';
import { existsSync } from 'fs';

const SMS_DB_PATH = `${homedir()}/Library/Messages/chat.db`;

if (!existsSync(SMS_DB_PATH)) {
  console.log('Messages database not found at:', SMS_DB_PATH);
  process.exit(1);
}

const db = new Database(SMS_DB_PATH, { readonly: true });

// Get all EmiratesNBD messages
const messages = db.prepare(`
  SELECT
    m.text,
    datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime') as date
  FROM message m
  JOIN handle h ON m.handle_id = h.ROWID
  WHERE h.id LIKE '%EmiratesNBD%'
  ORDER BY m.date DESC
  LIMIT 50
`).all();

console.log(`Found ${messages.length} EmiratesNBD messages\n`);

// Look for potential salary/income patterns
const incomeKeywords = ['راتب', 'salary', 'إيداع', 'deposit', 'credit', 'تحويل', 'transfer', 'received'];

messages.forEach((msg, i) => {
  const text = msg.text || '';
  const hasIncome = incomeKeywords.some(k => text.toLowerCase().includes(k));

  if (hasIncome) {
    console.log(`=== Message ${i + 1} (${msg.date}) - POTENTIAL INCOME ===`);
    console.log(text.substring(0, 300));
    console.log('');
  }
});

console.log('\n--- Sample of other messages ---');
messages.slice(0, 5).forEach((msg, i) => {
  console.log(`[${msg.date}] ${(msg.text || '').substring(0, 150)}...`);
});

db.close();
