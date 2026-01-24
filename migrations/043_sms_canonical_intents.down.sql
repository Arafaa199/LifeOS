-- Rollback: 043_sms_canonical_intents.down.sql

DROP VIEW IF EXISTS raw.sms_intent_breakdown;
DROP VIEW IF EXISTS raw.sms_coverage_summary;
DROP VIEW IF EXISTS raw.sms_missing_transactions;
DROP VIEW IF EXISTS raw.sms_daily_coverage;
DROP FUNCTION IF EXISTS raw.mark_sms_transaction_created(VARCHAR, INTEGER);
DROP FUNCTION IF EXISTS raw.classify_and_record_sms(VARCHAR, VARCHAR, TIMESTAMPTZ, VARCHAR, VARCHAR, VARCHAR, NUMERIC, NUMERIC, VARCHAR, VARCHAR);
DROP TABLE IF EXISTS raw.intent_mapping;
DROP TABLE IF EXISTS raw.sms_classifications;
