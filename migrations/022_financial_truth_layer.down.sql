-- Migration: 022_financial_truth_layer (rollback)

DROP FUNCTION IF EXISTS finance.refresh_financial_truth();
DROP VIEW IF EXISTS finance.v_dashboard_finance_summary;
DROP MATERIALIZED VIEW IF EXISTS finance.mv_spending_anomalies;
DROP MATERIALIZED VIEW IF EXISTS finance.mv_income_stability;
DROP MATERIALIZED VIEW IF EXISTS finance.mv_category_velocity;
DROP MATERIALIZED VIEW IF EXISTS finance.mv_monthly_spend;
