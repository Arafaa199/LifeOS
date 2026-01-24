BEGIN;

-- Cashflow Events
SELECT finance.import_cashflow_event('import-event-bank-loan-arrives-2025-02-06', '2025-02-06', 'Bank Loan Arrives', 50000, 'income', 'critical', 'CRITICAL - loan disbursement');
SELECT finance.import_cashflow_event('import-event-bnpl-payoff-2025-02-01', '2025-02-01', 'BNPL Payoff', -1500, 'expense', 'high', 'Tabby+Baseeta');
SELECT finance.import_cashflow_event('import-event-tabby-payment-1-4-2025-02-15', '2025-02-15', 'Tabby Payment 1/4', -1575, 'expense', 'high', 'Monitor+SSD+Smart');
SELECT finance.import_cashflow_event('import-event-tabby-payment-2-4-2025-03-15', '2025-03-15', 'Tabby Payment 2/4', -1575, 'expense', 'medium', '');
SELECT finance.import_cashflow_event('import-event-us-passport-2025-03-15', '2025-03-15', 'US Passport', -700, 'expense', 'high', 'DEADLINE');
SELECT finance.import_cashflow_event('import-event-mri---physio-2025-03-15', '2025-03-15', 'MRI + Physio', -2500, 'expense', 'critical', 'Health');
SELECT finance.import_cashflow_event('import-event-tabby-payment-3-4-2025-04-15', '2025-04-15', 'Tabby Payment 3/4', -1575, 'expense', 'medium', '');
SELECT finance.import_cashflow_event('import-event-car-customs-2025-05-15', '2025-05-15', 'Car Customs', -5000, 'expense', 'high', 'Family helping 5k');
SELECT finance.import_cashflow_event('import-event-tabby-payment-4-4-2025-05-15', '2025-05-15', 'Tabby Payment 4/4', -1575, 'expense', 'medium', 'TABBY DONE');

-- Wishlist Items
SELECT finance.import_wishlist_item('import-wishlist-mri-shoulder', 'MRI Shoulder', 1500, 'critical', 'health', '2025-03-01', 'Injury diagnosis');
SELECT finance.import_wishlist_item('import-wishlist-physiotherapy', 'Physiotherapy', 1000, 'critical', 'health', '2025-04-01', 'Post-MRI');
SELECT finance.import_wishlist_item('import-wishlist-lab-tests', 'Lab Tests', 1750, 'high', 'health', '2025-06-01', 'Full health panel');
SELECT finance.import_wishlist_item('import-wishlist-bjj-gi', 'BJJ Gi', 800, 'medium', 'health', '2025-04-01', 'Training gear');
SELECT finance.import_wishlist_item('import-wishlist-samsung-49--monitor', 'Samsung 49" Monitor', 4000, 'high', 'tech', '2025-02-01', '4 months Tabby');
SELECT finance.import_wishlist_item('import-wishlist-4tb-ssd', '4TB SSD', 800, 'high', 'tech', '2025-02-01', 'Fast storage');
SELECT finance.import_wishlist_item('import-wishlist-smart-door-knob', 'Smart Door Knob', 500, 'medium', 'tech', '2025-02-01', 'Home automation');
SELECT finance.import_wishlist_item('import-wishlist-smart-thermostat', 'Smart Thermostat', 1000, 'medium', 'tech', '2025-02-01', 'FCU control');
SELECT finance.import_wishlist_item('import-wishlist-10-20tb-hdd', '10-20TB HDD', 1500, 'low', 'tech', '2025-09-01', 'NAS storage');
SELECT finance.import_wishlist_item('import-wishlist-mini-cameras', 'Mini Cameras', 500, 'low', 'security', '2025-11-01', 'Projects');
SELECT finance.import_wishlist_item('import-wishlist-security-cameras', 'Security Cameras', 1500, 'low', 'security', '2025-11-01', 'Home');
SELECT finance.import_wishlist_item('import-wishlist-mous-amg-bag', 'Mous AMG Bag', 1500, 'low', 'other', '2025-12-01', '');
SELECT finance.import_wishlist_item('import-wishlist-rope-dart', 'Rope Dart', 200, 'low', 'other', '2025-12-01', 'Fun');
SELECT finance.import_wishlist_item('import-wishlist-ibanez-tod10n', 'Ibanez TOD10N', 3000, 'low', 'other', '2026-06-01', 'Guitar');
SELECT finance.import_wishlist_item('import-wishlist-voron-3d-printer', 'Voron 3D Printer', 5000, 'low', 'other', '2026-06-01', 'After loan done');

-- Budgets (current month)
INSERT INTO finance.budgets (month, category, budget_amount, notes)
VALUES ('2026-01-01', 'Groceries', 3700, 'Worst: 4,700')
ON CONFLICT (month, category) DO UPDATE SET budget_amount = EXCLUDED.budget_amount, notes = EXCLUDED.notes, updated_at = NOW();
INSERT INTO finance.budgets (month, category, budget_amount, notes)
VALUES ('2026-01-01', 'Health/Supplements', 400, 'Rogaine/Collagen/Vits')
ON CONFLICT (month, category) DO UPDATE SET budget_amount = EXCLUDED.budget_amount, notes = EXCLUDED.notes, updated_at = NOW();
INSERT INTO finance.budgets (month, category, budget_amount, notes)
VALUES ('2026-01-01', 'DEWA', 850, 'Summer buffer')
ON CONFLICT (month, category) DO UPDATE SET budget_amount = EXCLUDED.budget_amount, notes = EXCLUDED.notes, updated_at = NOW();
INSERT INTO finance.budgets (month, category, budget_amount, notes)
VALUES ('2026-01-01', 'Phone', 419, 'Du - 18th')
ON CONFLICT (month, category) DO UPDATE SET budget_amount = EXCLUDED.budget_amount, notes = EXCLUDED.notes, updated_at = NOW();
INSERT INTO finance.budgets (month, category, budget_amount, notes)
VALUES ('2026-01-01', 'Internet', 188, 'e& - 22nd')
ON CONFLICT (month, category) DO UPDATE SET budget_amount = EXCLUDED.budget_amount, notes = EXCLUDED.notes, updated_at = NOW();
INSERT INTO finance.budgets (month, category, budget_amount, notes)
VALUES ('2026-01-01', 'Subscriptions', 400, 'Claude Pro - 12th')
ON CONFLICT (month, category) DO UPDATE SET budget_amount = EXCLUDED.budget_amount, notes = EXCLUDED.notes, updated_at = NOW();
INSERT INTO finance.budgets (month, category, budget_amount, notes)
VALUES ('2026-01-01', 'Petrol', 500, '')
ON CONFLICT (month, category) DO UPDATE SET budget_amount = EXCLUDED.budget_amount, notes = EXCLUDED.notes, updated_at = NOW();
INSERT INTO finance.budgets (month, category, budget_amount, notes)
VALUES ('2026-01-01', 'Haircut', 350, '')
ON CONFLICT (month, category) DO UPDATE SET budget_amount = EXCLUDED.budget_amount, notes = EXCLUDED.notes, updated_at = NOW();
INSERT INTO finance.budgets (month, category, budget_amount, notes)
VALUES ('2026-01-01', 'Car Wash', 150, '')
ON CONFLICT (month, category) DO UPDATE SET budget_amount = EXCLUDED.budget_amount, notes = EXCLUDED.notes, updated_at = NOW();
INSERT INTO finance.budgets (month, category, budget_amount, notes)
VALUES ('2026-01-01', 'Loan Payment', 4583, '5th (worst case 10%)')
ON CONFLICT (month, category) DO UPDATE SET budget_amount = EXCLUDED.budget_amount, notes = EXCLUDED.notes, updated_at = NOW();
INSERT INTO finance.budgets (month, category, budget_amount, notes)
VALUES ('2026-01-01', 'Rent', 9000, '27k quarterly amortized')
ON CONFLICT (month, category) DO UPDATE SET budget_amount = EXCLUDED.budget_amount, notes = EXCLUDED.notes, updated_at = NOW();

-- Recurring Items (skip if exists by name)
INSERT INTO finance.recurring_items (name, amount, type, cadence, day_of_month, next_due_date, notes, is_active)
SELECT 'Du Mobile', 419, 'expense', 'monthly', 18, MAKE_DATE(EXTRACT(YEAR FROM CURRENT_DATE)::int, EXTRACT(MONTH FROM CURRENT_DATE)::int, 18), '', true
WHERE NOT EXISTS (SELECT 1 FROM finance.recurring_items WHERE name = 'Du Mobile');
INSERT INTO finance.recurring_items (name, amount, type, cadence, day_of_month, next_due_date, notes, is_active)
SELECT 'e& Internet', 188, 'expense', 'monthly', 22, MAKE_DATE(EXTRACT(YEAR FROM CURRENT_DATE)::int, EXTRACT(MONTH FROM CURRENT_DATE)::int, 22), '', true
WHERE NOT EXISTS (SELECT 1 FROM finance.recurring_items WHERE name = 'e& Internet');
INSERT INTO finance.recurring_items (name, amount, type, cadence, day_of_month, next_due_date, notes, is_active)
SELECT 'Claude Pro', 400, 'expense', 'monthly', 12, MAKE_DATE(EXTRACT(YEAR FROM CURRENT_DATE)::int, EXTRACT(MONTH FROM CURRENT_DATE)::int, 12), '', true
WHERE NOT EXISTS (SELECT 1 FROM finance.recurring_items WHERE name = 'Claude Pro');
INSERT INTO finance.recurring_items (name, amount, type, cadence, day_of_month, next_due_date, notes, is_active)
SELECT 'Bank Loan', 4583, 'expense', 'monthly', 5, MAKE_DATE(EXTRACT(YEAR FROM CURRENT_DATE)::int, EXTRACT(MONTH FROM CURRENT_DATE)::int, 5), '12 payments, 50k principal + 5k interest', true
WHERE NOT EXISTS (SELECT 1 FROM finance.recurring_items WHERE name = 'Bank Loan');
INSERT INTO finance.recurring_items (name, amount, type, cadence, day_of_month, next_due_date, notes, is_active)
SELECT 'HTB Academy', 1800, 'expense', 'yearly', NULL, '2025-03-04', 'Annual renewal', true
WHERE NOT EXISTS (SELECT 1 FROM finance.recurring_items WHERE name = 'HTB Academy');
INSERT INTO finance.recurring_items (name, amount, type, cadence, day_of_month, next_due_date, notes, is_active)
SELECT 'HTB Lab', 770, 'expense', 'yearly', NULL, '2025-07-03', 'Annual renewal', true
WHERE NOT EXISTS (SELECT 1 FROM finance.recurring_items WHERE name = 'HTB Lab');
INSERT INTO finance.recurring_items (name, amount, type, cadence, day_of_month, next_due_date, notes, is_active)
SELECT 'Rent Q1 2025', 27000, 'expense', 'quarterly', NULL, '2025-02-22', '', true
WHERE NOT EXISTS (SELECT 1 FROM finance.recurring_items WHERE name = 'Rent Q1 2025');
INSERT INTO finance.recurring_items (name, amount, type, cadence, day_of_month, next_due_date, notes, is_active)
SELECT 'Rent Q2 2025', 27000, 'expense', 'quarterly', NULL, '2025-05-22', '', true
WHERE NOT EXISTS (SELECT 1 FROM finance.recurring_items WHERE name = 'Rent Q2 2025');
INSERT INTO finance.recurring_items (name, amount, type, cadence, day_of_month, next_due_date, notes, is_active)
SELECT 'Rent Q3 2025', 27000, 'expense', 'quarterly', NULL, '2025-08-22', '', true
WHERE NOT EXISTS (SELECT 1 FROM finance.recurring_items WHERE name = 'Rent Q3 2025');
INSERT INTO finance.recurring_items (name, amount, type, cadence, day_of_month, next_due_date, notes, is_active)
SELECT 'Rent Q4 2025', 27000, 'expense', 'quarterly', NULL, '2025-11-22', '', true
WHERE NOT EXISTS (SELECT 1 FROM finance.recurring_items WHERE name = 'Rent Q4 2025');
INSERT INTO finance.recurring_items (name, amount, type, cadence, day_of_month, next_due_date, notes, is_active)
SELECT 'Rent Q1 2026', 27000, 'expense', 'quarterly', NULL, '2026-02-22', '', true
WHERE NOT EXISTS (SELECT 1 FROM finance.recurring_items WHERE name = 'Rent Q1 2026');

COMMIT;

