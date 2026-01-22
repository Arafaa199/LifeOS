-- Migration: 019_finalize_receipts (rollback)

DROP FUNCTION IF EXISTS finance.finalize_pending_receipts();
DROP FUNCTION IF EXISTS finance.finalize_receipt(INTEGER);
