-- Migration 036: Rollback Ingestion Health Views + Gap Detection

DROP FUNCTION IF EXISTS ops.get_ingestion_health_json();
DROP VIEW IF EXISTS ops.ingestion_health_summary;
DROP VIEW IF EXISTS ops.ingestion_health;
DROP VIEW IF EXISTS ops.ingestion_gaps;
