-- Migration: 021_receipt_ops_report (rollback)

DROP FUNCTION IF EXISTS finance.receipt_ops_detail();
DROP VIEW IF EXISTS finance.receipt_ops_report;
