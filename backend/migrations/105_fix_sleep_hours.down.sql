-- Migration 105 down: Clear backfilled sleep_hours (function reverts to 094 version without hours columns)
UPDATE life.daily_facts
SET sleep_hours = NULL,
    deep_sleep_hours = NULL;
