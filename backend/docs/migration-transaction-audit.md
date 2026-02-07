# Migration Transaction Wrapper Audit

Generated: 2026-02-07 19:21:09 UTC

## Summary

| Type | Total | Wrapped | Unwrapped | Coverage |
|------|-------|---------|-----------|----------|
| UP migrations | 140 | 48 | 92 | 34.2% |
| DOWN migrations | 140 | 43 | 97 | 30.7% |

## Risk Assessment

Migrations without transaction wrappers may leave the database in an inconsistent
state if they fail partway through execution. PostgreSQL DDL is transactional,
so multi-statement migrations should use `BEGIN` and `COMMIT` for atomicity.

**Impact of unwrapped migrations:**
- Partial application on failure requires manual cleanup
- No automatic rollback on error
- Potential for orphaned objects or missing constraints

**Recommendation:**
- New migrations should always include BEGIN/COMMIT
- Existing unwrapped migrations should be noted but NOT retroactively edited
  (editing applied migrations breaks the migration checksum/history)

## Unwrapped UP Migrations (92 files)

| File | Risk Notes |
|------|------------|
| 006_create_life_schema.up.sql | Low - early schema setup, likely simple |
| 010_finance_planning.up.sql | Low - early schema setup, likely simple |
| 011_timezone_consistency.up.sql | Low - early schema setup, likely simple |
| 012_receipt_ingestion.up.sql | Low - early schema setup, likely simple |
| 018_receipts_nullable_columns.up.sql | Low - early schema setup, likely simple |
| 019_finalize_receipts.up.sql | Low - early schema setup, likely simple |
| 019_receipt_template_tracking.up.sql | Low - early schema setup, likely simple |
| 020_harden_receipt_ingestion.up.sql | Low - early schema setup, likely simple |
| 021_receipt_ops_report.up.sql | Low - early schema setup, likely simple |
| 022_financial_truth_layer.up.sql | Low - early schema setup, likely simple |
| 023_location_tracking.up.sql | Low - early schema setup, likely simple |
| 024_behavioral_events.up.sql | Low - early schema setup, likely simple |
| 025_calorie_balance.up.sql | Low - early schema setup, likely simple |
| 026_github_activity.up.sql | Low - early schema setup, likely simple |
| 027_correlation_views.up.sql | Low - early schema setup, likely simple |
| 028_cross_domain_anomalies.up.sql | Low - early schema setup, likely simple |
| 029_finance_daily_mtd_views.up.sql | Low - early schema setup, likely simple |
| 030_budget_status_view.up.sql | Low - early schema setup, likely simple |
| 031_finance_dashboard_function.up.sql | Low - early schema setup, likely simple |
| 032_ops_pipeline_health.up.sql | Low - early schema setup, likely simple |
| 033_system_feeds_status.up.sql | Low - early schema setup, likely simple |
| 034_daily_confidence_view.up.sql | Low - early schema setup, likely simple |
| 035_sms_events_view.up.sql | Low - early schema setup, likely simple |
| 036_ingestion_health_gaps.up.sql | Low - early schema setup, likely simple |
| 037_confidence_decay_reprocess.up.sql | Low - early schema setup, likely simple |
| 038_finance_budget_engine.up.sql | Low - early schema setup, likely simple |
| 039_source_trust_scores.up.sql | Low - early schema setup, likely simple |
| 040_daily_life_summary.up.sql | Low - early schema setup, likely simple |
| 041_finance_canonical.up.sql | Low - early schema setup, likely simple |
| 041_weekly_insight_markdown.up.sql | Low - early schema setup, likely simple |
| 042_anomaly_explanations.up.sql | Low - early schema setup, likely simple |
| 042_fix_daily_summary_finance.up.sql | Low - early schema setup, likely simple |
| 043_sleep_spend_correlation.up.sql | Low - early schema setup, likely simple |
| 043_sms_canonical_intents.up.sql | Low - early schema setup, likely simple |
| 044_screen_sleep_aggregation.up.sql | Low - early schema setup, likely simple |
| 045_workload_health_correlation.up.sql | Low - early schema setup, likely simple |
| 046_daily_coverage_status.up.sql | Low - early schema setup, likely simple |
| 046_finance_daily_coverage.up.sql | Low - early schema setup, likely simple |
| 047_fix_client_id_constraint.up.sql | Low - early schema setup, likely simple |
| 060_coverage_audit_view.up.sql | Medium - established patterns, check complexity |
| 061_sms_intent_enum.up.sql | Medium - established patterns, check complexity |
| 062_raw_events_resolution.up.sql | Medium - established patterns, check complexity |
| 063_finance_timeline_view.up.sql | Medium - established patterns, check complexity |
| 064_daily_summary_timeline.up.sql | Medium - established patterns, check complexity |
| 067_grocery_nutrition_view.up.sql | Medium - established patterns, check complexity |
| 068_calendar_schema.up.sql | Medium - established patterns, check complexity |
| 069_healthkit_complete_schema.up.sql | Medium - established patterns, check complexity |
| 070_data_coverage_audit.up.sql | Medium - established patterns, check complexity |
| 071_canonical_daily_summary.up.sql | Medium - established patterns, check complexity |
| 072_meal_inference_engine.up.sql | Medium - established patterns, check complexity |
| 073_continuity_verification.up.sql | Medium - established patterns, check complexity |
| 074_meal_coverage_gaps.up.sql | Medium - established patterns, check complexity |
| 075_coverage_truth.up.sql | Medium - established patterns, check complexity |
| 079_receipt_item_brands.up.sql | Medium - established patterns, check complexity |
| 080_expand_nutrition_ingredients.up.sql | Medium - established patterns, check complexity |
| 081_sync_runs.up.sql | Medium - established patterns, check complexity |
| 087_github_activity_widget.up.sql | Medium - established patterns, check complexity |
| 088_receipt_first_finalization.up.sql | Medium - established patterns, check complexity |
| 089_dashboard_auto_refresh.up.sql | Medium - established patterns, check complexity |
| 090_whoop_direct_integration.up.sql | Medium - established patterns, check complexity |
| 091_fix_whoop_feed_triggers.up.sql | Medium - established patterns, check complexity |
| 092_fix_healthkit_timeseries_sample_types.up.sql | Medium - established patterns, check complexity |
| 093_domains_status_and_freshness_fix.up.sql | Medium - established patterns, check complexity |
| 101_calendar_dashboard.up.sql | Review - recent migration without wrapper |
| 102_reminders_schema.up.sql | Review - recent migration without wrapper |
| 104_github_feed_threshold.up.sql | Review - recent migration without wrapper |
| 105_fix_sleep_hours.up.sql | Review - recent migration without wrapper |
| 106_expand_ranked_insights.up.sql | Review - recent migration without wrapper |
| 107_category_velocity_insights.up.sql | Review - recent migration without wrapper |
| 109_monthly_calendar_summary.up.sql | Review - recent migration without wrapper |
| 112_weekly_report_calendar_reminders.up.sql | Review - recent migration without wrapper |
| 113_fix_receipt_feed_threshold.up.sql | Review - recent migration without wrapper |
| 117_reminders_bidirectional.up.sql | Review - recent migration without wrapper |
| 118_notes_index.up.sql | Review - recent migration without wrapper |
| 119_normalized_finance_view.up.sql | Review - recent migration without wrapper |
| 120_rewire_daily_facts_to_normalized.up.sql | Review - recent migration without wrapper |
| 121_fix_silent_trigger_failures.up.sql | Review - recent migration without wrapper |
| 122_deprecate_competing_pipeline.up.sql | Review - recent migration without wrapper |
| 123_deterministic_rebuild.up.sql | Review - recent migration without wrapper |
| 129_fx_pairing.up.sql | Review - recent migration without wrapper |
| 131_recurring_due_advance.up.sql | Review - recent migration without wrapper |
| 132_nutrition_food_database.up.sql | Review - recent migration without wrapper |
| 136_schema_migrations_table.up.sql | Review - recent migration without wrapper |
| 152_fasting_hours_since_meal.up.sql | Review - recent migration without wrapper |
| 153_home_events.up.sql | Review - recent migration without wrapper |
| 154_weather_and_location.up.sql | Review - recent migration without wrapper |
| 160_fix_weight_source_priority.up.sql | Review - recent migration without wrapper |
| 162_water_mood_logging.up.sql | Review - recent migration without wrapper |
| 163_installments.up.sql | Review - recent migration without wrapper |
| 165_supplement_definitions.up.sql | Review - recent migration without wrapper |
| 166_calendar_bidirectional_sync.up.sql | Review - recent migration without wrapper |
| 167_receipt_auto_match.up.sql | Review - recent migration without wrapper |

## Unwrapped DOWN Migrations (97 files)

| File | Risk Notes |
|------|------------|
| 006_create_life_schema.down.sql | DOWN migrations are rarely executed |
| 010_finance_planning.down.sql | DOWN migrations are rarely executed |
| 011_timezone_consistency.down.sql | DOWN migrations are rarely executed |
| 012_receipt_ingestion.down.sql | DOWN migrations are rarely executed |
| 018_receipts_nullable_columns.down.sql | DOWN migrations are rarely executed |
| 019_finalize_receipts.down.sql | DOWN migrations are rarely executed |
| 019_receipt_template_tracking.down.sql | DOWN migrations are rarely executed |
| 020_harden_receipt_ingestion.down.sql | DOWN migrations are rarely executed |
| 021_receipt_ops_report.down.sql | DOWN migrations are rarely executed |
| 022_financial_truth_layer.down.sql | DOWN migrations are rarely executed |
| 023_location_tracking.down.sql | DOWN migrations are rarely executed |
| 024_behavioral_events.down.sql | DOWN migrations are rarely executed |
| 025_calorie_balance.down.sql | DOWN migrations are rarely executed |
| 026_github_activity.down.sql | DOWN migrations are rarely executed |
| 027_correlation_views.down.sql | DOWN migrations are rarely executed |
| 028_cross_domain_anomalies.down.sql | DOWN migrations are rarely executed |
| 029_finance_daily_mtd_views.down.sql | DOWN migrations are rarely executed |
| 030_budget_status_view.down.sql | DOWN migrations are rarely executed |
| 031_finance_dashboard_function.down.sql | DOWN migrations are rarely executed |
| 032_ops_pipeline_health.down.sql | DOWN migrations are rarely executed |
| 033_system_feeds_status.down.sql | DOWN migrations are rarely executed |
| 034_daily_confidence_view.down.sql | DOWN migrations are rarely executed |
| 035_sms_events_view.down.sql | DOWN migrations are rarely executed |
| 036_ingestion_health_gaps.down.sql | DOWN migrations are rarely executed |
| 037_confidence_decay_reprocess.down.sql | DOWN migrations are rarely executed |
| 038_finance_budget_engine.down.sql | DOWN migrations are rarely executed |
| 039_source_trust_scores.down.sql | DOWN migrations are rarely executed |
| 040_daily_life_summary.down.sql | DOWN migrations are rarely executed |
| 041_finance_canonical.down.sql | DOWN migrations are rarely executed |
| 041_weekly_insight_markdown.down.sql | DOWN migrations are rarely executed |
| 042_anomaly_explanations.down.sql | DOWN migrations are rarely executed |
| 042_fix_daily_summary_finance.down.sql | DOWN migrations are rarely executed |
| 043_sleep_spend_correlation.down.sql | DOWN migrations are rarely executed |
| 043_sms_canonical_intents.down.sql | DOWN migrations are rarely executed |
| 044_screen_sleep_aggregation.down.sql | DOWN migrations are rarely executed |
| 045_workload_health_correlation.down.sql | DOWN migrations are rarely executed |
| 046_daily_coverage_status.down.sql | DOWN migrations are rarely executed |
| 046_finance_daily_coverage.down.sql | DOWN migrations are rarely executed |
| 047_fix_client_id_constraint.down.sql | DOWN migrations are rarely executed |
| 060_coverage_audit_view.down.sql | DOWN migrations are rarely executed |
| 061_sms_intent_enum.down.sql | DOWN migrations are rarely executed |
| 062_raw_events_resolution.down.sql | DOWN migrations are rarely executed |
| 063_finance_timeline_view.down.sql | DOWN migrations are rarely executed |
| 064_daily_summary_timeline.down.sql | DOWN migrations are rarely executed |
| 067_grocery_nutrition_view.down.sql | DOWN migrations are rarely executed |
| 068_calendar_schema.down.sql | DOWN migrations are rarely executed |
| 069_healthkit_complete_schema.down.sql | DOWN migrations are rarely executed |
| 070_data_coverage_audit.down.sql | DOWN migrations are rarely executed |
| 071_canonical_daily_summary.down.sql | DOWN migrations are rarely executed |
| 072_meal_inference_engine.down.sql | DOWN migrations are rarely executed |
| 073_continuity_verification.down.sql | DOWN migrations are rarely executed |
| 074_meal_coverage_gaps.down.sql | DOWN migrations are rarely executed |
| 075_coverage_truth.down.sql | DOWN migrations are rarely executed |
| 079_receipt_item_brands.down.sql | DOWN migrations are rarely executed |
| 080_expand_nutrition_ingredients.down.sql | DOWN migrations are rarely executed |
| 081_sync_runs.down.sql | DOWN migrations are rarely executed |
| 087_github_activity_widget.down.sql | DOWN migrations are rarely executed |
| 088_receipt_first_finalization.down.sql | DOWN migrations are rarely executed |
| 089_dashboard_auto_refresh.down.sql | DOWN migrations are rarely executed |
| 090_whoop_direct_integration.down.sql | DOWN migrations are rarely executed |
| 091_fix_whoop_feed_triggers.down.sql | DOWN migrations are rarely executed |
| 092_fix_healthkit_timeseries_sample_types.down.sql | DOWN migrations are rarely executed |
| 093_domains_status_and_freshness_fix.down.sql | DOWN migrations are rarely executed |
| 094_reliability_fixes.down.sql | DOWN migrations are rarely executed |
| 100_backfill_daily_health.down.sql | DOWN migrations are rarely executed |
| 101_calendar_dashboard.down.sql | DOWN migrations are rarely executed |
| 102_reminders_schema.down.sql | DOWN migrations are rarely executed |
| 104_github_feed_threshold.down.sql | DOWN migrations are rarely executed |
| 105_fix_sleep_hours.down.sql | DOWN migrations are rarely executed |
| 106_expand_ranked_insights.down.sql | DOWN migrations are rarely executed |
| 107_category_velocity_insights.down.sql | DOWN migrations are rarely executed |
| 109_monthly_calendar_summary.down.sql | DOWN migrations are rarely executed |
| 112_weekly_report_calendar_reminders.down.sql | DOWN migrations are rarely executed |
| 113_fix_receipt_feed_threshold.down.sql | DOWN migrations are rarely executed |
| 117_reminders_bidirectional.down.sql | DOWN migrations are rarely executed |
| 118_notes_index.down.sql | DOWN migrations are rarely executed |
| 119_normalized_finance_view.down.sql | DOWN migrations are rarely executed |
| 120_rewire_daily_facts_to_normalized.down.sql | DOWN migrations are rarely executed |
| 121_fix_silent_trigger_failures.down.sql | DOWN migrations are rarely executed |
| 122_deprecate_competing_pipeline.down.sql | DOWN migrations are rarely executed |
| 123_deterministic_rebuild.down.sql | DOWN migrations are rarely executed |
| 125_backfill_normalized_from_legacy.down.sql | DOWN migrations are rarely executed |
| 129_fx_pairing.down.sql | DOWN migrations are rarely executed |
| 130_exclude_noneconomic.down.sql | DOWN migrations are rarely executed |
| 131_recurring_due_advance.down.sql | DOWN migrations are rarely executed |
| 132_nutrition_food_database.down.sql | DOWN migrations are rarely executed |
| 136_schema_migrations_table.down.sql | DOWN migrations are rarely executed |
| 152_fasting_hours_since_meal.down.sql | DOWN migrations are rarely executed |
| 153_home_events.down.sql | DOWN migrations are rarely executed |
| 154_weather_and_location.down.sql | DOWN migrations are rarely executed |
| 160_fix_weight_source_priority.down.sql | DOWN migrations are rarely executed |
| 162_water_mood_logging.down.sql | DOWN migrations are rarely executed |
| 163_installments.down.sql | DOWN migrations are rarely executed |
| 164_mood_dashboard.down.sql | DOWN migrations are rarely executed |
| 165_supplement_definitions.down.sql | DOWN migrations are rarely executed |
| 166_calendar_bidirectional_sync.down.sql | DOWN migrations are rarely executed |
| 167_receipt_auto_match.down.sql | DOWN migrations are rarely executed |

## Best Practices for New Migrations

```sql
-- Migration: NNN_description
-- Purpose: Brief description

BEGIN;

-- Your DDL statements here
CREATE TABLE ...;
ALTER TABLE ...;

-- Verification (optional)
-- SELECT ...;

COMMIT;
```

## Notes

- This audit was generated automatically and may have false positives/negatives
- Some migrations intentionally avoid transactions (e.g., CREATE INDEX CONCURRENTLY)
- The audit checks for BEGIN/COMMIT keywords but doesn't validate structure
