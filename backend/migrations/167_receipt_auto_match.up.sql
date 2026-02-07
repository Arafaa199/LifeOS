-- Migration 167: Receipt Item Auto-Matching
-- Improves receipt→nutrition matching from ~1% to estimated 40-60%

-- Function to clean receipt item descriptions for better matching
CREATE OR REPLACE FUNCTION finance.clean_receipt_item(description TEXT)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    cleaned TEXT;
BEGIN
    -- Remove weight/volume suffixes with duplicates (e.g., "330g 330" → "")
    cleaned := regexp_replace(description, '\s*,?\s*\d+[gGmMlLkK]+\s*\d*$', '', 'g');
    -- Remove standalone numbers at end
    cleaned := regexp_replace(cleaned, '\s+\d+$', '');
    -- Normalize whitespace
    cleaned := regexp_replace(cleaned, '\s+', ' ', 'g');
    -- Trim
    cleaned := trim(cleaned);
    RETURN cleaned;
END;
$$;

-- List of non-food items to skip
CREATE TABLE IF NOT EXISTS finance.receipt_non_food_items (
    pattern TEXT PRIMARY KEY,
    reason TEXT
);

INSERT INTO finance.receipt_non_food_items (pattern, reason) VALUES
    ('delivery charge', 'service fee'),
    ('service fee', 'service fee'),
    ('bag fee', 'service fee'),
    ('carrier bag', 'packaging'),
    ('plastic bag', 'packaging'),
    ('paper bag', 'packaging'),
    ('discount', 'adjustment'),
    ('promo', 'adjustment'),
    ('coupon', 'adjustment'),
    ('refund', 'adjustment'),
    ('deposit', 'deposit'),
    ('bottle deposit', 'deposit')
ON CONFLICT (pattern) DO NOTHING;

-- Function to auto-match a single receipt item
CREATE OR REPLACE FUNCTION finance.auto_match_receipt_item(
    p_item_id INTEGER,
    p_confidence_threshold NUMERIC DEFAULT 0.4
)
RETURNS TABLE(
    item_id INTEGER,
    matched_food_id INTEGER,
    food_name TEXT,
    confidence NUMERIC,
    matched BOOLEAN
)
LANGUAGE plpgsql AS $$
DECLARE
    v_description TEXT;
    v_cleaned TEXT;
    v_food_id INTEGER;
    v_food_name TEXT;
    v_confidence NUMERIC;
BEGIN
    -- Get item description
    SELECT item_description INTO v_description
    FROM finance.receipt_items
    WHERE id = p_item_id;

    IF v_description IS NULL THEN
        RETURN QUERY SELECT p_item_id, NULL::INTEGER, NULL::TEXT, 0.0::NUMERIC, false;
        RETURN;
    END IF;

    -- Check if it's a non-food item
    IF EXISTS (
        SELECT 1 FROM finance.receipt_non_food_items
        WHERE lower(v_description) LIKE '%' || pattern || '%'
    ) THEN
        RETURN QUERY SELECT p_item_id, NULL::INTEGER, 'Non-food item'::TEXT, 0.0::NUMERIC, false;
        RETURN;
    END IF;

    -- Clean the description
    v_cleaned := finance.clean_receipt_item(v_description);

    -- Search for matching food
    SELECT f.id, f.name, similarity(f.name, v_cleaned)
    INTO v_food_id, v_food_name, v_confidence
    FROM nutrition.search_foods(v_cleaned, 1, false) f
    LIMIT 1;

    IF v_food_id IS NOT NULL AND v_confidence >= p_confidence_threshold THEN
        -- Update the receipt item with the match
        UPDATE finance.receipt_items
        SET matched_food_id = v_food_id,
            match_confidence = v_confidence,
            is_user_confirmed = false,
            nutrition_snapshot = (
                SELECT jsonb_build_object(
                    'calories_per_100g', calories_per_100g,
                    'protein_per_100g', protein_per_100g,
                    'carbs_per_100g', carbs_per_100g,
                    'fat_per_100g', fat_per_100g
                )
                FROM nutrition.foods WHERE id = v_food_id
            )
        WHERE id = p_item_id;

        RETURN QUERY SELECT p_item_id, v_food_id, v_food_name, v_confidence, true;
    ELSE
        RETURN QUERY SELECT p_item_id, v_food_id, v_food_name, COALESCE(v_confidence, 0.0), false;
    END IF;
END;
$$;

-- Function to auto-match all unmatched receipt items
CREATE OR REPLACE FUNCTION finance.auto_match_all_receipt_items(
    p_confidence_threshold NUMERIC DEFAULT 0.4
)
RETURNS TABLE(
    total_processed INTEGER,
    total_matched INTEGER,
    match_rate NUMERIC
)
LANGUAGE plpgsql AS $$
DECLARE
    v_item RECORD;
    v_processed INTEGER := 0;
    v_matched INTEGER := 0;
BEGIN
    FOR v_item IN
        SELECT ri.id
        FROM finance.receipt_items ri
        WHERE ri.matched_food_id IS NULL
        ORDER BY ri.id
    LOOP
        v_processed := v_processed + 1;

        IF EXISTS (
            SELECT 1 FROM finance.auto_match_receipt_item(v_item.id, p_confidence_threshold)
            WHERE matched = true
        ) THEN
            v_matched := v_matched + 1;
        END IF;
    END LOOP;

    RETURN QUERY SELECT
        v_processed,
        v_matched,
        CASE WHEN v_processed > 0
            THEN ROUND(100.0 * v_matched / v_processed, 1)
            ELSE 0.0
        END;
END;
$$;

-- Update item_description_clean with better cleaning
UPDATE finance.receipt_items
SET item_description_clean = finance.clean_receipt_item(item_description)
WHERE item_description_clean IS NULL
   OR item_description_clean = lower(item_description);

-- Run auto-matching on all existing unmatched items
DO $$
DECLARE
    result RECORD;
BEGIN
    SELECT * INTO result FROM finance.auto_match_all_receipt_items(0.4);
    RAISE NOTICE 'Auto-match complete: % processed, % matched (%.1f%%)',
        result.total_processed, result.total_matched, result.match_rate;
END $$;

-- Trigger to auto-match new receipt items on insert
CREATE OR REPLACE FUNCTION finance.trigger_auto_match_receipt_item()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    -- Only auto-match if not already matched
    IF NEW.matched_food_id IS NULL THEN
        PERFORM finance.auto_match_receipt_item(NEW.id, 0.4);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_match_receipt_item ON finance.receipt_items;

CREATE TRIGGER trg_auto_match_receipt_item
    AFTER INSERT ON finance.receipt_items
    FOR EACH ROW
    EXECUTE FUNCTION finance.trigger_auto_match_receipt_item();

COMMENT ON FUNCTION finance.clean_receipt_item IS 'Cleans receipt item descriptions for better food matching';
COMMENT ON FUNCTION finance.auto_match_receipt_item IS 'Auto-matches a single receipt item to nutrition.foods';
COMMENT ON FUNCTION finance.auto_match_all_receipt_items IS 'Auto-matches all unmatched receipt items';
COMMENT ON FUNCTION finance.trigger_auto_match_receipt_item IS 'Trigger function to auto-match on insert';
