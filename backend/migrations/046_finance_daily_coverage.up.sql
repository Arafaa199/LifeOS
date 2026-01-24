-- Migration 046: Finance Daily Coverage Status View
-- Date: 2026-01-25
-- Purpose: Single view showing daily SMS/receipt coverage status

-- Create view showing daily coverage metrics
CREATE OR REPLACE VIEW finance.daily_coverage_status AS
WITH date_range AS (
  -- Last 90 days
  SELECT generate_series(
    CURRENT_DATE - 90,
    CURRENT_DATE,
    '1 day'::interval
  )::DATE as day
),
sms_coverage AS (
  SELECT
    finance.to_business_date(transaction_at) as day,
    COUNT(*) as sms_transactions
  FROM finance.transactions
  WHERE external_id LIKE 'sms:%'
  GROUP BY finance.to_business_date(transaction_at)
),
receipt_coverage AS (
  SELECT
    r.receipt_date as day,
    COUNT(DISTINCT r.id) as receipt_count,
    COUNT(DISTINCT r.linked_transaction_id) FILTER (WHERE r.linked_transaction_id IS NOT NULL) as receipts_linked
  FROM finance.receipts r
  WHERE r.receipt_date IS NOT NULL
  GROUP BY r.receipt_date
),
anomaly_counts AS (
  SELECT
    day,
    array_length(anomalies, 1) as anomaly_count
  FROM insights.daily_anomalies
)
SELECT
  dr.day,
  COALESCE(sc.sms_transactions, 0) as sms_transactions,
  COALESCE(rc.receipt_count, 0) as receipt_count,
  COALESCE(rc.receipts_linked, 0) as receipts_linked,
  CASE
    WHEN rc.receipt_count > 0 THEN
      ROUND((rc.receipts_linked::NUMERIC / rc.receipt_count) * 100, 1)
    ELSE NULL
  END as receipt_link_pct,
  COALESCE(ac.anomaly_count, 0) as anomaly_count,
  -- Coverage status
  CASE
    WHEN sc.sms_transactions > 0 AND rc.receipt_count > 0 THEN 'full'
    WHEN sc.sms_transactions > 0 OR rc.receipt_count > 0 THEN 'partial'
    WHEN dr.day = CURRENT_DATE THEN 'pending'  -- Today might still have data coming
    WHEN dr.day >= CURRENT_DATE - 7 THEN 'missing_recent'  -- Last 7 days
    ELSE 'missing_old'  -- Older than 7 days
  END as coverage_status,
  -- Gap detection
  CASE
    WHEN sc.sms_transactions = 0 AND dr.day < CURRENT_DATE - 1 THEN true
    ELSE false
  END as is_sms_gap,
  -- Metadata
  CURRENT_TIMESTAMP as as_of_timestamp
FROM date_range dr
LEFT JOIN sms_coverage sc ON dr.day = sc.day
LEFT JOIN receipt_coverage rc ON dr.day = rc.day
LEFT JOIN anomaly_counts ac ON dr.day = ac.day
ORDER BY dr.day DESC;

COMMENT ON VIEW finance.daily_coverage_status IS 'Daily SMS/receipt coverage status for last 90 days. Shows transaction counts, receipt linkage %, anomaly counts, and gap detection.';

-- Create summary view for dashboard
CREATE OR REPLACE VIEW finance.coverage_summary AS
SELECT
  COUNT(*) FILTER (WHERE coverage_status = 'full') as days_full_coverage,
  COUNT(*) FILTER (WHERE coverage_status = 'partial') as days_partial_coverage,
  COUNT(*) FILTER (WHERE coverage_status LIKE 'missing%') as days_missing,
  COUNT(*) FILTER (WHERE is_sms_gap AND day >= CURRENT_DATE - 30) as sms_gaps_30d,
  ROUND(AVG(receipt_link_pct) FILTER (WHERE receipt_link_pct IS NOT NULL), 1) as avg_receipt_link_pct,
  SUM(sms_transactions) as total_sms_transactions,
  SUM(receipt_count) as total_receipts,
  SUM(anomaly_count) as total_anomalies,
  MIN(day) FILTER (WHERE is_sms_gap AND day >= CURRENT_DATE - 30) as first_recent_gap,
  MAX(day) FILTER (WHERE is_sms_gap AND day >= CURRENT_DATE - 30) as last_recent_gap
FROM finance.daily_coverage_status
WHERE day >= CURRENT_DATE - 90;

COMMENT ON VIEW finance.coverage_summary IS 'Aggregated coverage metrics for last 90 days. Shows full/partial/missing days, SMS gaps, receipt linkage %, and anomaly totals.';
