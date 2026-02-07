-- Rollback: Receipt Item Auto-Matching

-- Drop trigger first
DROP TRIGGER IF EXISTS trg_auto_match_receipt_item ON finance.receipt_items;

-- Clear auto-matched items (keep user-confirmed ones)
UPDATE finance.receipt_items
SET matched_food_id = NULL,
    match_confidence = NULL,
    nutrition_snapshot = NULL
WHERE is_user_confirmed = false;

-- Drop functions
DROP FUNCTION IF EXISTS finance.trigger_auto_match_receipt_item();
DROP FUNCTION IF EXISTS finance.auto_match_all_receipt_items(NUMERIC);
DROP FUNCTION IF EXISTS finance.auto_match_receipt_item(INTEGER, NUMERIC);
DROP FUNCTION IF EXISTS finance.clean_receipt_item(TEXT);

-- Drop non-food items table
DROP TABLE IF EXISTS finance.receipt_non_food_items;
