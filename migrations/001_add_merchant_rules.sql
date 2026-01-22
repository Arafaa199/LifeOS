-- Migration 001: Add comprehensive merchant categorization rules
-- Run on nexus: psql -U nexus -d nexus -f migrations/001_add_merchant_rules.sql

BEGIN;

-- Clear existing rules to avoid conflicts
TRUNCATE finance.merchant_rules;

-- ============================================================================
-- UAE-SPECIFIC MERCHANTS (Emirates NBD transactions)
-- ============================================================================

-- Grocery stores
INSERT INTO finance.merchant_rules (merchant_pattern, category, subcategory, is_grocery, is_food_related, priority) VALUES
    ('%CARREFOUR%', 'Grocery', 'Supermarket', TRUE, TRUE, 10),
    ('%carrefouruae%', 'Grocery', 'Supermarket', TRUE, TRUE, 10),
    ('%LULU%', 'Grocery', 'Supermarket', TRUE, TRUE, 10),
    ('%SPINNEYS%', 'Grocery', 'Supermarket', TRUE, TRUE, 10),
    ('%CHOITHRAMS%', 'Grocery', 'Supermarket', TRUE, TRUE, 10),
    ('%GRANDIOSE%', 'Grocery', 'Supermarket', TRUE, TRUE, 10),
    ('%WAITROSE%', 'Grocery', 'Supermarket', TRUE, TRUE, 10),
    ('%UNION COOP%', 'Grocery', 'Supermarket', TRUE, TRUE, 10),
    ('%SHARJAH COOP%', 'Grocery', 'Supermarket', TRUE, TRUE, 10),
    ('%TALABAT MART%', 'Grocery', 'Delivery', TRUE, TRUE, 10),
    ('%NOON MINUTES%', 'Grocery', 'Delivery', TRUE, TRUE, 10),
    ('%KIBSONS%', 'Grocery', 'Fresh Produce', TRUE, TRUE, 10);

-- Food Delivery & Restaurants
INSERT INTO finance.merchant_rules (merchant_pattern, category, subcategory, is_restaurant, is_food_related, priority) VALUES
    ('%CAREEM FOOD%', 'Food', 'Delivery', TRUE, TRUE, 15),
    ('%TALABAT%', 'Food', 'Delivery', TRUE, TRUE, 10),
    ('%ZOMATO%', 'Food', 'Delivery', TRUE, TRUE, 10),
    ('%DELIVEROO%', 'Food', 'Delivery', TRUE, TRUE, 10),
    ('%NOON FOOD%', 'Food', 'Delivery', TRUE, TRUE, 10),
    ('%STARBUCKS%', 'Food', 'Coffee', TRUE, TRUE, 10),
    ('%TIM HORTONS%', 'Food', 'Coffee', TRUE, TRUE, 10),
    ('%COFFEE BEAN%', 'Food', 'Coffee', TRUE, TRUE, 10),
    ('%COSTA COFFEE%', 'Food', 'Coffee', TRUE, TRUE, 10),
    ('%MCDONALD%', 'Food', 'Fast Food', TRUE, TRUE, 10),
    ('%KFC%', 'Food', 'Fast Food', TRUE, TRUE, 10),
    ('%BURGER KING%', 'Food', 'Fast Food', TRUE, TRUE, 10),
    ('%SUBWAY%', 'Food', 'Fast Food', TRUE, TRUE, 10),
    ('%PAPA JOHN%', 'Food', 'Fast Food', TRUE, TRUE, 10),
    ('%PIZZA HUT%', 'Food', 'Fast Food', TRUE, TRUE, 10),
    ('%DOMINO%', 'Food', 'Fast Food', TRUE, TRUE, 10),
    ('%SHAKE SHACK%', 'Food', 'Fast Food', TRUE, TRUE, 10),
    ('%FIVE GUYS%', 'Food', 'Fast Food', TRUE, TRUE, 10),
    ('%CHIPOTLE%', 'Food', 'Fast Food', TRUE, TRUE, 10),
    ('%NANDO%', 'Food', 'Restaurant', TRUE, TRUE, 10),
    ('%CHILI%S%', 'Food', 'Restaurant', TRUE, TRUE, 10),
    ('%TGI FRIDAY%', 'Food', 'Restaurant', TRUE, TRUE, 10),
    ('%P.F. CHANG%', 'Food', 'Restaurant', TRUE, TRUE, 10),
    ('%CHEESECAKE FACTORY%', 'Food', 'Restaurant', TRUE, TRUE, 10);

-- Transport
INSERT INTO finance.merchant_rules (merchant_pattern, category, subcategory, is_grocery, is_restaurant, is_food_related, priority) VALUES
    ('%CAREEM%', 'Transport', 'Rideshare', FALSE, FALSE, FALSE, 5),
    ('%CAREEM QUIK%', 'Transport', 'Rideshare', FALSE, FALSE, FALSE, 15),
    ('%UBER%', 'Transport', 'Rideshare', FALSE, FALSE, FALSE, 5),
    ('%UBER EATS%', 'Food', 'Delivery', FALSE, TRUE, TRUE, 15),
    ('%RTA%', 'Transport', 'Public', FALSE, FALSE, FALSE, 10),
    ('%SALIK%', 'Transport', 'Toll', FALSE, FALSE, FALSE, 10),
    ('%DARB%', 'Transport', 'Toll', FALSE, FALSE, FALSE, 10),
    ('%ENOC%', 'Transport', 'Fuel', FALSE, FALSE, FALSE, 10),
    ('%EMARAT%', 'Transport', 'Fuel', FALSE, FALSE, FALSE, 10),
    ('%ADNOC%', 'Transport', 'Fuel', FALSE, FALSE, FALSE, 10),
    ('%PARKING%', 'Transport', 'Parking', FALSE, FALSE, FALSE, 8);

-- Shopping & E-commerce
INSERT INTO finance.merchant_rules (merchant_pattern, category, subcategory, is_grocery, is_restaurant, is_food_related, priority) VALUES
    ('%AMAZON%', 'Shopping', 'Online', FALSE, FALSE, FALSE, 8),
    ('%NOON%', 'Shopping', 'Online', FALSE, FALSE, FALSE, 8),
    ('%NAMSHI%', 'Shopping', 'Fashion', FALSE, FALSE, FALSE, 10),
    ('%SHEIN%', 'Shopping', 'Fashion', FALSE, FALSE, FALSE, 10),
    ('%IKEA%', 'Shopping', 'Home', FALSE, FALSE, FALSE, 10),
    ('%HOME CENTRE%', 'Shopping', 'Home', FALSE, FALSE, FALSE, 10),
    ('%ACE HARDWARE%', 'Shopping', 'Hardware', FALSE, FALSE, FALSE, 10),
    ('%GEANT%', 'Shopping', 'Department', FALSE, FALSE, FALSE, 8),
    ('%CARREFOUR CITY%', 'Shopping', 'Convenience', FALSE, FALSE, FALSE, 10);

-- Utilities & Bills
INSERT INTO finance.merchant_rules (merchant_pattern, category, subcategory, is_grocery, is_restaurant, is_food_related, priority) VALUES
    ('%DEWA%', 'Utilities', 'Electricity', FALSE, FALSE, FALSE, 10),
    ('%FEWA%', 'Utilities', 'Electricity', FALSE, FALSE, FALSE, 10),
    ('%SEWA%', 'Utilities', 'Electricity', FALSE, FALSE, FALSE, 10),
    ('%DU%', 'Utilities', 'Telecom', FALSE, FALSE, FALSE, 8),
    ('%ETISALAT%', 'Utilities', 'Telecom', FALSE, FALSE, FALSE, 10),
    ('%ELIFE%', 'Utilities', 'Internet', FALSE, FALSE, FALSE, 10);

-- Healthcare
INSERT INTO finance.merchant_rules (merchant_pattern, category, subcategory, is_grocery, is_restaurant, is_food_related, priority) VALUES
    ('%PHARMACY%', 'Health', 'Pharmacy', FALSE, FALSE, FALSE, 8),
    ('%ASTER%', 'Health', 'Pharmacy', FALSE, FALSE, FALSE, 10),
    ('%LIFE PHARMACY%', 'Health', 'Pharmacy', FALSE, FALSE, FALSE, 10),
    ('%BOOTS%', 'Health', 'Pharmacy', FALSE, FALSE, FALSE, 10),
    ('%HOSPITAL%', 'Health', 'Medical', FALSE, FALSE, FALSE, 8),
    ('%CLINIC%', 'Health', 'Medical', FALSE, FALSE, FALSE, 8),
    ('%MEDICLINIC%', 'Health', 'Medical', FALSE, FALSE, FALSE, 10),
    ('%NMC%', 'Health', 'Medical', FALSE, FALSE, FALSE, 10);

-- Fitness & Wellness
INSERT INTO finance.merchant_rules (merchant_pattern, category, subcategory, is_grocery, is_restaurant, is_food_related, priority) VALUES
    ('%GYM%', 'Fitness', 'Gym', FALSE, FALSE, FALSE, 8),
    ('%FITNESS FIRST%', 'Fitness', 'Gym', FALSE, FALSE, FALSE, 10),
    ('%GOLD%S GYM%', 'Fitness', 'Gym', FALSE, FALSE, FALSE, 10),
    ('%BARRY%S%', 'Fitness', 'Gym', FALSE, FALSE, FALSE, 10),
    ('%F45%', 'Fitness', 'Gym', FALSE, FALSE, FALSE, 10),
    ('%CROSSFIT%', 'Fitness', 'Gym', FALSE, FALSE, FALSE, 10),
    ('%SPA%', 'Wellness', 'Spa', FALSE, FALSE, FALSE, 8),
    ('%SALON%', 'Wellness', 'Personal Care', FALSE, FALSE, FALSE, 8);

-- Entertainment & Subscriptions
INSERT INTO finance.merchant_rules (merchant_pattern, category, subcategory, is_grocery, is_restaurant, is_food_related, priority) VALUES
    ('%NETFLIX%', 'Entertainment', 'Streaming', FALSE, FALSE, FALSE, 10),
    ('%SPOTIFY%', 'Entertainment', 'Streaming', FALSE, FALSE, FALSE, 10),
    ('%APPLE%', 'Entertainment', 'Services', FALSE, FALSE, FALSE, 8),
    ('%YOUTUBE%', 'Entertainment', 'Streaming', FALSE, FALSE, FALSE, 10),
    ('%DISNEY%', 'Entertainment', 'Streaming', FALSE, FALSE, FALSE, 10),
    ('%CINEMA%', 'Entertainment', 'Movies', FALSE, FALSE, FALSE, 8),
    ('%VOX%', 'Entertainment', 'Movies', FALSE, FALSE, FALSE, 10),
    ('%REEL%', 'Entertainment', 'Movies', FALSE, FALSE, FALSE, 10),
    ('%NOVO%', 'Entertainment', 'Movies', FALSE, FALSE, FALSE, 10);

-- Banking & Finance
INSERT INTO finance.merchant_rules (merchant_pattern, category, subcategory, is_grocery, is_restaurant, is_food_related, priority) VALUES
    ('%ATM%', 'Cash', 'ATM', FALSE, FALSE, FALSE, 5),
    ('%TRANSFER%', 'Transfer', 'Bank Transfer', FALSE, FALSE, FALSE, 5),
    ('%WESTERN UNION%', 'Transfer', 'Remittance', FALSE, FALSE, FALSE, 10),
    ('%EXCHANGE%', 'Transfer', 'Exchange', FALSE, FALSE, FALSE, 8),
    ('%AL ANSARI%', 'Transfer', 'Exchange', FALSE, FALSE, FALSE, 10),
    ('%UAE EXCHANGE%', 'Transfer', 'Exchange', FALSE, FALSE, FALSE, 10);

-- ============================================================================
-- SAUDI ARABIA MERCHANTS (AlRajhi transactions)
-- ============================================================================

INSERT INTO finance.merchant_rules (merchant_pattern, category, subcategory, is_grocery, is_restaurant, is_food_related, priority) VALUES
    ('%PANDA%', 'Grocery', 'Supermarket', TRUE, FALSE, TRUE, 10),
    ('%DANUBE%', 'Grocery', 'Supermarket', TRUE, FALSE, TRUE, 10),
    ('%TAMIMI%', 'Grocery', 'Supermarket', TRUE, FALSE, TRUE, 10),
    ('%OTHAIM%', 'Grocery', 'Supermarket', TRUE, FALSE, TRUE, 10),
    ('%FARM%', 'Grocery', 'Supermarket', TRUE, FALSE, TRUE, 8),
    ('%HUNGERSTATION%', 'Food', 'Delivery', FALSE, TRUE, TRUE, 10),
    ('%JAHEZ%', 'Food', 'Delivery', FALSE, TRUE, TRUE, 10),
    ('%TOY%S R US%', 'Shopping', 'Toys', FALSE, FALSE, FALSE, 10),
    ('%EXTRA%', 'Shopping', 'Electronics', FALSE, FALSE, FALSE, 10),
    ('%JARIR%', 'Shopping', 'Books/Office', FALSE, FALSE, FALSE, 10),
    ('%STC%', 'Utilities', 'Telecom', FALSE, FALSE, FALSE, 10),
    ('%MOBILY%', 'Utilities', 'Telecom', FALSE, FALSE, FALSE, 10),
    ('%ZAIN%', 'Utilities', 'Telecom', FALSE, FALSE, FALSE, 10);

-- ============================================================================
-- GENERAL PATTERNS (lower priority, catch-all)
-- ============================================================================

INSERT INTO finance.merchant_rules (merchant_pattern, category, subcategory, is_grocery, is_restaurant, is_food_related, priority) VALUES
    ('%RESTAURANT%', 'Food', 'Restaurant', FALSE, TRUE, TRUE, 3),
    ('%CAFE%', 'Food', 'Coffee', FALSE, TRUE, TRUE, 3),
    ('%COFFEE%', 'Food', 'Coffee', FALSE, TRUE, TRUE, 3),
    ('%BAKERY%', 'Food', 'Bakery', FALSE, TRUE, TRUE, 3),
    ('%SUPERMARKET%', 'Grocery', 'Supermarket', TRUE, FALSE, TRUE, 3),
    ('%MARKET%', 'Grocery', 'Market', TRUE, FALSE, TRUE, 2),
    ('%MINIMART%', 'Grocery', 'Convenience', TRUE, FALSE, TRUE, 5),
    ('%HOTEL%', 'Travel', 'Accommodation', FALSE, FALSE, FALSE, 3),
    ('%AIRLINE%', 'Travel', 'Flights', FALSE, FALSE, FALSE, 3),
    ('%FLY%', 'Travel', 'Flights', FALSE, FALSE, FALSE, 2);

COMMIT;

-- Show summary
SELECT category, COUNT(*) as rule_count
FROM finance.merchant_rules
GROUP BY category
ORDER BY rule_count DESC;
