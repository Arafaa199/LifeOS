-- Migration: 060_coverage_audit_view.down.sql
-- Purpose: Remove coverage audit views

DROP VIEW IF EXISTS finance.v_orphan_raw_events;
DROP VIEW IF EXISTS finance.v_coverage_summary;
DROP VIEW IF EXISTS finance.v_coverage_gaps;
