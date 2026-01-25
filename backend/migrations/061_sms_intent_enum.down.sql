-- Migration: 061_sms_intent_enum.down.sql
-- Purpose: Remove SMS intent enum type

DROP INDEX IF EXISTS raw.idx_sms_class_sms_intent;

ALTER TABLE raw.sms_classifications DROP COLUMN IF EXISTS sms_intent;
ALTER TABLE finance.raw_events DROP COLUMN IF EXISTS sms_intent;

DROP FUNCTION IF EXISTS finance.map_canonical_to_sms_intent(TEXT);

DROP TYPE IF EXISTS finance.sms_intent;
