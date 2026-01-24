#!/usr/bin/env node

/**
 * SMS Classifier - Deterministic regex-based message classification
 * Loads patterns from sms_regex_patterns.yaml
 *
 * Usage:
 *   import { SMSClassifier } from './sms-classifier.js';
 *   const classifier = new SMSClassifier();
 *   const result = classifier.classify(sender, text);
 */

import { readFileSync } from 'fs';
import { parse as parseYAML } from 'yaml';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Pattern file location - LifeOS-Ops is in Dev, not Infrastructure
const PATTERNS_FILE = join(__dirname, '../../../Dev/LifeOS-Ops/artifacts/sms_regex_patterns.yaml');

/**
 * Convert Python-style named groups (?P<name>...) to JavaScript (?<name>...)
 */
function convertPythonRegex(pattern) {
  return pattern.replace(/\(\?P</g, '(?<');
}

/**
 * Parse amount string to float
 */
function parseAmount(amountStr) {
  if (!amountStr) return null;
  return parseFloat(amountStr.replace(/,/g, ''));
}

/**
 * Normalize currency from Arabic to code
 */
function normalizeCurrency(currency, currencyMap) {
  if (!currency) return null;
  // Check if it's an Arabic currency name
  if (currencyMap && currencyMap[currency]) {
    return currencyMap[currency];
  }
  return currency.toUpperCase();
}

/**
 * SMS Classifier class
 */
export class SMSClassifier {
  constructor(patternsFile = PATTERNS_FILE) {
    this.patterns = this.loadPatterns(patternsFile);
    this.excludePatterns = this.compileExcludePatterns();
    this.bankPatterns = this.compileBankPatterns();
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
        compiled.push({
          name: pattern.name,
          regex: new RegExp(jsRegex, 'i'),
          reason: pattern.reason,
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
          compiled.push({
            name: pattern.name,
            intent: pattern.intent,
            regex: new RegExp(jsRegex, 'im'), // multiline + case insensitive
            entities: pattern.entities || [],
            category: pattern.category || null,
            confidence: pattern.confidence || 0.9,
            never_create_transaction: pattern.never_create_transaction || false,
          });
        } catch (err) {
          console.error(`Invalid pattern ${bankKey}.${pattern.name}: ${err.message}`);
        }
      }

      // Map all sender variations to the same patterns
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
   * Check if message should be excluded (OTP, promo, etc.)
   */
  shouldExclude(text) {
    for (const pattern of this.excludePatterns) {
      if (pattern.regex.test(text)) {
        return { excluded: true, reason: pattern.reason, pattern: pattern.name };
      }
    }
    return { excluded: false };
  }

  /**
   * Classify a single SMS message
   * @param {string} sender - Message sender ID (e.g., "EmiratesNBD")
   * @param {string} text - Message text
   * @param {string} msgDate - Message date (YYYY-MM-DD format)
   * @returns {object|null} Classification result or null if no match
   */
  classify(sender, text, msgDate = null) {
    if (!sender || !text) return null;

    // Check exclusions first
    const exclusion = this.shouldExclude(text);
    if (exclusion.excluded) {
      return {
        matched: false,
        excluded: true,
        exclusion_reason: exclusion.reason,
        exclusion_pattern: exclusion.pattern,
      };
    }

    // Find bank patterns
    const senderLower = sender.toLowerCase();
    const bank = this.bankPatterns[senderLower];
    if (!bank) {
      return {
        matched: false,
        excluded: false,
        reason: 'unknown_sender',
      };
    }

    // Try each pattern in order
    for (const pattern of bank.patterns) {
      const match = text.match(pattern.regex);
      if (match) {
        // Extract named groups
        const groups = match.groups || {};

        // Parse amount
        const amount = parseAmount(groups.amount);

        // Normalize currency
        const currencyMap = this.patterns.currencies?.arabic_names || {};
        const currency = normalizeCurrency(groups.currency, currencyMap);

        // Determine sign based on intent
        let signedAmount = amount;
        if (amount !== null) {
          switch (pattern.intent) {
            case 'expense':
            case 'transfer':
              signedAmount = -Math.abs(amount);
              break;
            case 'income':
            case 'refund':
              signedAmount = Math.abs(amount);
              break;
            case 'declined':
              signedAmount = null; // Declined transactions have no financial impact
              break;
          }
        }

        // Extract merchant (from various possible group names)
        const merchant = groups.merchant || groups.to || groups.from || groups.order || null;

        return {
          matched: true,
          excluded: false,
          pattern_name: pattern.name,
          intent: pattern.intent,
          amount: signedAmount,
          amount_abs: amount,
          currency: currency,
          merchant: merchant ? merchant.trim() : null,
          entities: groups,
          category: pattern.category,
          confidence: pattern.confidence,
          never_create_transaction: pattern.never_create_transaction,
          sender: sender,
          date: msgDate,
        };
      }
    }

    // No pattern matched
    return {
      matched: false,
      excluded: false,
      reason: 'no_pattern_match',
      sender: sender,
    };
  }

  /**
   * Get supported senders list
   */
  getSupportedSenders() {
    return Object.keys(this.bankPatterns);
  }

  /**
   * Get pattern statistics
   */
  getPatternStats() {
    const stats = {
      exclude_patterns: this.excludePatterns.length,
      banks: {},
    };

    for (const [sender, bank] of Object.entries(this.bankPatterns)) {
      if (!stats.banks[sender]) {
        stats.banks[sender] = bank.patterns.length;
      }
    }

    return stats;
  }
}

// CLI mode for testing
if (import.meta.url === `file://${process.argv[1]}`) {
  const classifier = new SMSClassifier();

  console.log('SMS Classifier loaded successfully');
  console.log('Supported senders:', classifier.getSupportedSenders().join(', '));
  console.log('Pattern stats:', classifier.getPatternStats());

  // Test with sample messages
  const testMessages = [
    { sender: 'EmiratesNBD', text: 'تم ايداع الراتب AED 23,500.00 في  حسابك' },
    { sender: 'EmiratesNBD', text: 'تمت عملية شراء بقيمة AED 165.00 لدى BARBERSHOP ,Dubai باستخدام بطاقة خصم' },
    { sender: 'JKB', text: 'You have an approved purchase trx on POS for SAR 20.00 on your card' },
    { sender: 'AlRajhiBank', text: 'PoS\nBy:8308;mada\nAmount:SAR 48\nAt:KAKAT' },
    { sender: 'EmiratesNBD', text: 'OTP: 123456 is your verification code' },
  ];

  console.log('\nTest classifications:');
  for (const msg of testMessages) {
    const result = classifier.classify(msg.sender, msg.text, '2026-01-24');
    console.log(`\n[${msg.sender}] ${msg.text.substring(0, 50)}...`);
    if (result.matched) {
      console.log(`  ✓ ${result.pattern_name} | ${result.intent} | ${result.currency} ${result.amount}`);
    } else if (result.excluded) {
      console.log(`  ✗ Excluded: ${result.exclusion_reason}`);
    } else {
      console.log(`  ? No match: ${result.reason}`);
    }
  }
}

export default SMSClassifier;
