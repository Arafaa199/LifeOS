-- Migration 020 Rollback: Financial Truth Engine Views

DROP VIEW IF EXISTS finance.v_financial_truth_summary;
DROP VIEW IF EXISTS finance.v_anomaly_baseline;
DROP VIEW IF EXISTS finance.v_income_stability;
DROP VIEW IF EXISTS finance.v_category_velocity;
DROP VIEW IF EXISTS finance.v_monthly_spend;
