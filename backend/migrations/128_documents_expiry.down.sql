-- Migration 128 rollback: Documents & Expiry Tracking

BEGIN;

DROP VIEW IF EXISTS life.v_documents_with_status;
DROP FUNCTION IF EXISTS life.renew_document(INT, DATE, VARCHAR, TEXT);
DROP FUNCTION IF EXISTS life.clear_document_reminders(INT);
DROP FUNCTION IF EXISTS life.create_document_reminders(INT);
DROP TRIGGER IF EXISTS trg_documents_updated_at ON life.documents;
DROP FUNCTION IF EXISTS life.set_documents_updated_at();
DROP TABLE IF EXISTS life.document_renewals;
DROP TABLE IF EXISTS life.document_reminders;
DROP TABLE IF EXISTS life.documents;

COMMIT;
