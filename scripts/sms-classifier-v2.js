#!/usr/bin/env node

/**
 * SMS Classifier v2 - Canonical Intent Classification
 *
 * Canonical Intents:
 *   FIN_TXN_APPROVED  - Financial transaction approved
 *   FIN_TXN_DECLINED  - Transaction declined
 *   FIN_TXN_REFUND    - Refund received
 *   FIN_BALANCE_UPDATE - Balance notification
 *   FIN_AUTH_CODE     - OTP/verification codes
 *   FIN_SECURITY_ALERT - Security alerts
 *   FIN_LOGIN_ALERT   - Login notifications
 *   FIN_INFO_ONLY     - Informational (statements, promos)
 *   IGNORE            - Not from tracked sender or malformed
 */

import { readFileSync } from 'fs';
import { parse as parseYAML } from 'yaml';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PATTERNS_FILE = join(__dirname, '../../../Dev/LifeOS-Ops/artifacts/sms_regex_patterns.yaml');

// Canonical intent mapping from legacy intents
const INTENT_MAP = {
  expense: 'FIN_TXN_APPROVED',
  income: 'FIN_TXN_APPROVED',
  transfer: 'FIN_TXN_APPROVED',
  atm: 'FIN_TXN_APPROVED',
  refund: 'FIN_TXN_REFUND',
  declined: 'FIN_TXN_DECLINED',
  otp: 'FIN_AUTH_CODE',
  security: 'FIN_SECURITY_ALERT',
  login: 'FIN_LOGIN_ALERT',
  info: 'FIN_INFO_ONLY',
  balance: 'FIN_BALANCE_UPDATE',
  promo: 'IGNORE',
};

// Intents that should create transactions
const TRANSACTION_INTENTS = ['FIN_TXN_APPROVED', 'FIN_TXN_REFUND'];

function convertPythonRegex(pattern) {
  return pattern.replace(/\(\?P</g, '(?<');
}

function parseAmount(amountStr) {
  if (!amountStr) return null;
  return parseFloat(amountStr.replace(/,/g, ''));
}

function normalizeCurrency(currency, currencyMap) {
  if (!currency) return null;
  if (currencyMap && currencyMap[currency]) {
    return currencyMap[currency];
  }
  return currency.toUpperCase();
}

export class SMSClassifierV2 {
  constructor(patternsFile = PATTERNS_FILE) {
    this.patterns = this.loadPatterns(patternsFile);
    this.excludePatterns = this.compileExcludePatterns();
    this.bankPatterns = this.compileBankPatterns();
    this.version = 'v2.0';
  }

  loadPatterns(filePath) {
    try {
      const content = readFileSync(filePath, 'utf8');
      return parseYAML(content);
    } catch (err) {
      console.error(`Failed to load patterns from ${filePath}: ${err.message}`);
      throw err;
    }
  }

  compileExcludePatterns() {
    const compiled = [];
    for (const pattern of this.patterns.exclude_patterns || []) {
      try {
        const jsRegex = convertPythonRegex(pattern.regex);
        // Determine canonical intent for exclusion
        let canonicalIntent = 'IGNORE';
        const reason = (pattern.reason || '').toLowerCase();
        if (reason.includes('otp') || reason.includes('verification') || reason.includes('authentication')) {
          canonicalIntent = 'FIN_AUTH_CODE';
        } else if (reason.includes('security') || reason.includes('protection')) {
          canonicalIntent = 'FIN_SECURITY_ALERT';
        } else if (reason.includes('login')) {
          canonicalIntent = 'FIN_LOGIN_ALERT';
        } else if (reason.includes('statement') || reason.includes('informational')) {
          canonicalIntent = 'FIN_INFO_ONLY';
        }

        compiled.push({
          name: pattern.name,
          regex: new RegExp(jsRegex, 'i'),
          reason: pattern.reason,
          canonicalIntent,
        });
      } catch (err) {
        console.error(`Invalid exclude pattern ${pattern.name}: ${err.message}`);
      }
    }
    return compiled;
  }

  compileBankPatterns() {
    const banks = {};
    const bankSections = ['emiratesnbd', 'alrajhibank', 'jkb', 'careem', 'amazon'];

    for (const bankKey of bankSections) {
      const bankConfig = this.patterns[bankKey];
      if (!bankConfig) continue;

      const senders = bankConfig.senders || [bankConfig.sender];
      const compiled = [];

      for (const pattern of bankConfig.patterns || []) {
        try {
          const jsRegex = convertPythonRegex(pattern.regex);
          const legacyIntent = pattern.intent;
          const canonicalIntent = INTENT_MAP[legacyIntent] || 'FIN_INFO_ONLY';

          compiled.push({
            name: pattern.name,
            legacyIntent,
            canonicalIntent,
            regex: new RegExp(jsRegex, 'im'),
            entities: pattern.entities || [],
            category: pattern.category || null,
            confidence: pattern.confidence || 0.9,
            neverCreateTransaction: pattern.never_create_transaction || false,
            shouldCreateTransaction: TRANSACTION_INTENTS.includes(canonicalIntent) && !pattern.never_create_transaction,
          });
        } catch (err) {
          console.error(`Invalid pattern ${bankKey}.${pattern.name}: ${err.message}`);
        }
      }

      for (const sender of senders) {
        banks[sender.toLowerCase()] = {
          config: bankConfig,
          patterns: compiled,
        };
      }
    }

    return banks;
  }

  /**
   * Classify with canonical intent - ALWAYS returns a classification
   */
  classify(sender, text, msgDate = null) {
    if (!sender || !text) {
      return {
        canonicalIntent: 'IGNORE',
        legacyIntent: null,
        shouldCreateTransaction: false,
        reason: 'empty_input',
        confidence: 0,
      };
    }

    // Check exclusions first
    for (const pattern of this.excludePatterns) {
      if (pattern.regex.test(text)) {
        return {
          canonicalIntent: pattern.canonicalIntent,
          legacyIntent: null,
          patternName: pattern.name,
          shouldCreateTransaction: false,
          excluded: true,
          exclusionReason: pattern.reason,
          confidence: 0.95,
          sender,
          date: msgDate,
        };
      }
    }

    // Find bank patterns
    const senderLower = sender.toLowerCase();
    const bank = this.bankPatterns[senderLower];
    if (!bank) {
      return {
        canonicalIntent: 'IGNORE',
        legacyIntent: null,
        shouldCreateTransaction: false,
        reason: 'unknown_sender',
        confidence: 0,
        sender,
        date: msgDate,
      };
    }

    // Try each pattern in order
    for (const pattern of bank.patterns) {
      const match = text.match(pattern.regex);
      if (match) {
        const groups = match.groups || {};
        const amount = parseAmount(groups.amount);
        const currencyMap = this.patterns.currencies?.arabic_names || {};
        const currency = normalizeCurrency(groups.currency, currencyMap);
        const merchant = groups.merchant || groups.to || groups.from || groups.order || null;

        // Calculate signed amount based on intent
        let signedAmount = amount;
        if (amount !== null) {
          switch (pattern.legacyIntent) {
            case 'expense':
            case 'transfer':
            case 'atm':
              signedAmount = -Math.abs(amount);
              break;
            case 'income':
            case 'refund':
              signedAmount = Math.abs(amount);
              break;
            case 'declined':
              signedAmount = null;
              break;
          }
        }

        return {
          canonicalIntent: pattern.canonicalIntent,
          legacyIntent: pattern.legacyIntent,
          patternName: pattern.name,
          shouldCreateTransaction: pattern.shouldCreateTransaction,
          confidence: pattern.confidence,
          amount: signedAmount,
          amountAbs: amount,
          currency,
          merchant: merchant ? merchant.trim() : null,
          entities: groups,
          category: pattern.category,
          sender,
          date: msgDate,
        };
      }
    }

    // No pattern matched - classify as INFO
    return {
      canonicalIntent: 'FIN_INFO_ONLY',
      legacyIntent: null,
      shouldCreateTransaction: false,
      reason: 'no_pattern_match',
      confidence: 0.5,
      sender,
      date: msgDate,
    };
  }

  /**
   * Batch classify messages
   */
  classifyBatch(messages) {
    return messages.map((msg) => ({
      input: msg,
      classification: this.classify(msg.sender, msg.text, msg.date),
    }));
  }

  /**
   * Get statistics
   */
  getStats() {
    return {
      version: this.version,
      excludePatterns: this.excludePatterns.length,
      banks: Object.fromEntries(
        Object.entries(this.bankPatterns).map(([sender, bank]) => [sender, bank.patterns.length])
      ),
      canonicalIntents: Object.keys(INTENT_MAP),
      transactionIntents: TRANSACTION_INTENTS,
    };
  }
}

// CLI mode
if (import.meta.url === `file://${process.argv[1]}`) {
  const classifier = new SMSClassifierV2();

  console.log('SMS Classifier v2 - Canonical Intents');
  console.log('=====================================');
  console.log('Stats:', JSON.stringify(classifier.getStats(), null, 2));

  const testMessages = [
    { sender: 'EmiratesNBD', text: 'تم ايداع الراتب AED 23,500.00 في  حسابك', date: '2026-01-03' },
    { sender: 'EmiratesNBD', text: 'تمت عملية شراء بقيمة AED 165.00 لدى BARBERSHOP ,Dubai باستخدام بطاقة خصم', date: '2026-01-12' },
    { sender: 'EmiratesNBD', text: 'OTP: 123456 is your verification code', date: '2026-01-24' },
    { sender: 'EmiratesNBD', text: 'تم توثيق عملية تسجيل دخول من جهاز جديد', date: '2026-01-24' },
    { sender: 'AlRajhiBank', text: 'PoS\nBy:8308;mada\nAmount:SAR 48\nAt:KAKAT', date: '2026-01-10' },
    { sender: 'Unknown', text: 'Random spam message', date: '2026-01-24' },
  ];

  console.log('\nTest Classifications:');
  console.log('---------------------');

  for (const msg of testMessages) {
    const result = classifier.classify(msg.sender, msg.text, msg.date);
    console.log(`\n[${msg.sender}] ${msg.text.substring(0, 50)}...`);
    console.log(`  Intent: ${result.canonicalIntent}`);
    console.log(`  Create TX: ${result.shouldCreateTransaction}`);
    if (result.amount) console.log(`  Amount: ${result.currency} ${result.amount}`);
    console.log(`  Confidence: ${result.confidence}`);
  }
}

export default SMSClassifierV2;
