#!/usr/bin/env node

/**
 * SMS Classifier Unit Tests
 * Tests the sms-classifier.js against known patterns
 *
 * Usage: node test-sms-classifier.js
 */

import { SMSClassifier } from './sms-classifier.js';

// Test cases organized by bank/sender
const testCases = [
  // ==========================================
  // EmiratesNBD Tests
  // ==========================================
  {
    name: 'EmiratesNBD: Salary deposit',
    sender: 'EmiratesNBD',
    text: 'تم ايداع الراتب AED 23,500.00 في  حسابك .101XXX79XXX04 الرصيد المتوفر هو AED 23,514.47',
    expected: {
      matched: true,
      intent: 'income',
      amount: 23500,
      currency: 'AED',
    },
  },
  {
    name: 'EmiratesNBD: Debit purchase',
    sender: 'EmiratesNBD',
    text: 'تمت عملية شراء بقيمة AED 165.00 لدى B 27 BARBERSHOP LLC ,Dubai باستخدام بطاقة خصم',
    expected: {
      matched: true,
      intent: 'expense',
      amount: -165,
      currency: 'AED',
      merchant: 'B 27 BARBERSHOP LLC',
    },
  },
  {
    name: 'EmiratesNBD: Credit purchase',
    sender: 'EmiratesNBD',
    text: 'تمت عملية شراء في AED 1,326.28 LOGIC UTILITIES DIST C,DUBAI على البطاقة 4695',
    expected: {
      matched: true,
      intent: 'expense',
      amount: -1326.28,
      currency: 'AED',
    },
  },
  {
    name: 'EmiratesNBD: Declined transaction',
    sender: 'EmiratesNBD',
    text: 'تم رفض معاملة بقيمة 250.00AED على بطاقتك',
    expected: {
      matched: true,
      intent: 'declined',
      amount: null, // Declined should have null amount
      never_create_transaction: true,
    },
  },
  {
    name: 'EmiratesNBD: ATM Withdrawal',
    sender: 'EmiratesNBD',
    text: 'لقد قمت بسحب مبلغ AED 500.00 مستخدما بطاقة الصراف الآلي من DUBAI ATM',
    expected: {
      matched: true,
      intent: 'expense',
      amount: -500,
      currency: 'AED',
    },
  },
  {
    name: 'EmiratesNBD: Refund',
    sender: 'EmiratesNBD',
    text: 'لقد تم إعادة مبلغ عملية شراء بقيمة AED 50.00',
    expected: {
      matched: true,
      intent: 'refund',
      amount: 50, // Refund should be positive
      currency: 'AED',
    },
  },

  // ==========================================
  // AlRajhiBank Tests
  // ==========================================
  {
    name: 'AlRajhiBank: POS purchase',
    sender: 'AlRajhiBank',
    text: 'PoS\nBy:8308;mada-Apple Pay\nAmount:SAR 48\nAt:KAKAT CO',
    expected: {
      matched: true,
      intent: 'expense',
      amount: -48,
      currency: 'SAR',
    },
  },
  {
    name: 'AlRajhiBank: International POS',
    sender: 'AlRajhiBank',
    text: 'PoS International\nBy:8308;mada\nAmount:SAR 30.91\nCountry:Netherlands\nAt:UBR* PENDING.UBER.COM',
    expected: {
      matched: true,
      intent: 'expense',
      amount: -30.91,
      currency: 'SAR',
    },
  },
  {
    name: 'AlRajhiBank: Online Purchase',
    sender: 'AlRajhiBank',
    text: 'Online Purchase\nBy:8308;mada\nFrom:4281\nAmount:SAR 988.60\nAt:Amazon SA',
    expected: {
      matched: true,
      intent: 'expense',
      amount: -988.6,
      currency: 'SAR',
    },
  },
  {
    name: 'AlRajhiBank: Refund',
    sender: 'AlRajhiBank',
    text: 'Refund PoS\nBy:8308;mada\nAmount:SAR 38.94\nAt:Amazon SA',
    expected: {
      matched: true,
      intent: 'refund',
      amount: 38.94,
      currency: 'SAR',
    },
  },

  // ==========================================
  // JKB Tests
  // ==========================================
  {
    name: 'JKB: POS purchase',
    sender: 'JKB',
    text: 'You have an approved purchase trx on POS for SAR 20.00 on your card #5513***3612, at Boufia Majid Ahmed Ibr, JEDDAH',
    expected: {
      matched: true,
      intent: 'expense',
      amount: -20,
      currency: 'SAR',
    },
  },
  {
    name: 'JKB: E-commerce purchase',
    sender: 'JKB',
    text: 'You have an approved Ecommerce trx  for SAR 33.84 on your card #5361***9793, at UBER * PENDING, Vorden',
    expected: {
      matched: true,
      intent: 'expense',
      amount: -33.84,
      currency: 'SAR',
    },
  },
  {
    name: 'JKB: Declined (insufficient funds)',
    sender: 'JKB',
    text: 'You have a declined trx on your card # 5361***9793 from Hungerstation, Riyadh,  for SAR 136.00 due to insufficient funds',
    expected: {
      matched: true,
      intent: 'declined',
      amount: null,
      never_create_transaction: true,
    },
  },
  {
    name: 'JKB: Account fee (Arabic with code currency)',
    sender: 'JKB',
    text: 'تم قيد مبلغ 1  JOD  على حسابكم  التوفير  0266XXXXXXX0013020000  عمولة تدني رصيد الحساب',
    expected: {
      matched: true,
      intent: 'expense',
      amount: -1,
      currency: 'JOD',
    },
  },

  // ==========================================
  // Exclusion Tests
  // ==========================================
  {
    name: 'Exclude: OTP message',
    sender: 'EmiratesNBD',
    text: 'OTP: 123456 is your verification code',
    expected: {
      excluded: true,
      matched: false,
    },
  },
  {
    name: 'Exclude: Arabic OTP',
    sender: 'EmiratesNBD',
    text: 'رمز التحقق الخاص بك هو 654321',
    expected: {
      excluded: true,
      matched: false,
    },
  },
  {
    name: 'Exclude: Apple Pay setup',
    sender: 'EmiratesNBD',
    text: 'Your card is now ready for contactless payments with Apple Pay',
    expected: {
      excluded: true,
      matched: false,
    },
  },
  {
    name: 'Exclude: Credit card statement',
    sender: 'EmiratesNBD',
    text: 'كشف حساب مصغّر: المستحق 500 AED',
    expected: {
      excluded: true,
      matched: false,
    },
  },

  // ==========================================
  // Edge Cases
  // ==========================================
  {
    name: 'Edge: Amount with comma (23,500.00)',
    sender: 'EmiratesNBD',
    text: 'تم ايداع الراتب AED 23,500.00 في  حسابك',
    expected: {
      matched: true,
      amount_abs: 23500,
    },
  },
  {
    name: 'Edge: Small amount no decimals',
    sender: 'AlRajhiBank',
    text: 'PoS\nBy:8308;mada\nAmount:SAR 5\nAt:SHOP',
    expected: {
      matched: true,
      amount: -5,
    },
  },
  {
    name: 'Edge: Unknown sender',
    sender: 'UnknownBank',
    text: 'Some transaction message',
    expected: {
      matched: false,
      reason: 'unknown_sender',
    },
  },

  // ==========================================
  // CAREEM and Amazon Tests
  // ==========================================
  {
    name: 'CAREEM: Order refund',
    sender: 'CAREEM',
    text: 'Hi Arafa, your order 145001255 has been cancelled and AED 255.95 has been refunded to your Wallet.',
    expected: {
      matched: true,
      intent: 'refund',
      amount: 255.95,
      currency: 'AED',
    },
  },
  {
    name: 'Amazon: Refund notification',
    sender: 'Amazon',
    text: 'Refund Issued: Amount SAR 195.05 (EYSOO Protein Shaker Bottle 20...).',
    expected: {
      matched: true,
      intent: 'refund',
      amount: 195.05,
      currency: 'SAR',
    },
  },
];

// Run tests
function runTests() {
  console.log('SMS Classifier Unit Tests');
  console.log('='.repeat(50));
  console.log('');

  let passed = 0;
  let failed = 0;
  const failures = [];

  const classifier = new SMSClassifier();

  for (const test of testCases) {
    const result = classifier.classify(test.sender, test.text);
    let testPassed = true;
    const errors = [];

    // Check each expected field
    for (const [key, expectedValue] of Object.entries(test.expected)) {
      const actualValue = result[key];

      // Handle floating point comparison
      if (typeof expectedValue === 'number' && typeof actualValue === 'number') {
        if (Math.abs(actualValue - expectedValue) > 0.01) {
          testPassed = false;
          errors.push(`${key}: expected ${expectedValue}, got ${actualValue}`);
        }
      } else if (actualValue !== expectedValue) {
        testPassed = false;
        errors.push(`${key}: expected ${expectedValue}, got ${actualValue}`);
      }
    }

    if (testPassed) {
      passed++;
      console.log(`\x1b[32m[PASS]\x1b[0m ${test.name}`);
    } else {
      failed++;
      console.log(`\x1b[31m[FAIL]\x1b[0m ${test.name}`);
      for (const error of errors) {
        console.log(`       - ${error}`);
      }
      failures.push({ name: test.name, errors, result });
    }
  }

  console.log('');
  console.log('='.repeat(50));
  console.log(`Total: ${testCases.length}`);
  console.log(`Passed: ${passed}`);
  console.log(`Failed: ${failed}`);
  console.log('='.repeat(50));

  if (failed > 0) {
    console.log('');
    console.log('Failed Tests Details:');
    for (const failure of failures) {
      console.log(`\n${failure.name}:`);
      console.log('  Result:', JSON.stringify(failure.result, null, 2).split('\n').join('\n  '));
    }
    process.exit(1);
  } else {
    console.log('\x1b[32mAll tests passed!\x1b[0m');
    process.exit(0);
  }
}

// Additional pattern statistics
function showStats() {
  const classifier = new SMSClassifier();
  const stats = classifier.getPatternStats();

  console.log('');
  console.log('Pattern Statistics:');
  console.log('-'.repeat(30));
  console.log(`Exclude patterns: ${stats.exclude_patterns}`);
  for (const [sender, count] of Object.entries(stats.banks)) {
    console.log(`${sender}: ${count} patterns`);
  }
  console.log('-'.repeat(30));
  console.log(`Supported senders: ${classifier.getSupportedSenders().join(', ')}`);
}

// Main
console.log('');
runTests();
showStats();
