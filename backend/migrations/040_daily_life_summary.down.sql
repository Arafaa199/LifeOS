-- Migration: 040_daily_life_summary (DOWN)
-- Purpose: Rollback TASK-O1 - Remove life.get_daily_summary function

DROP FUNCTION IF EXISTS life.get_daily_summary(DATE);
