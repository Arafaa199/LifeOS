-- Rollback: 163_installments

DROP TRIGGER IF EXISTS trg_installments_feed_status ON finance.installments;
DROP FUNCTION IF EXISTS finance.update_installments_feed_status();
DROP FUNCTION IF EXISTS finance.record_installment_payment(INT);
DROP TRIGGER IF EXISTS trg_installments_updated ON finance.installments;
DROP FUNCTION IF EXISTS finance.update_installments_timestamp();
DROP VIEW IF EXISTS finance.v_active_installments;
DROP TABLE IF EXISTS finance.installments;

DELETE FROM life.feed_status_live WHERE source = 'installments';
