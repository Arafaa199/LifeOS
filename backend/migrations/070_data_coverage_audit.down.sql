-- Rollback: Data Coverage Audit Views
-- Task: TASK-VERIFY.1

DROP VIEW IF EXISTS life.v_coverage_summary_30d;
DROP VIEW IF EXISTS life.v_domain_coverage_matrix;
DROP VIEW IF EXISTS life.v_data_coverage_gaps;
