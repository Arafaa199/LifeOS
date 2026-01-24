-- Migration: 025_calorie_balance (rollback)
-- Removes calorie balance views

DROP VIEW IF EXISTS facts.weekly_calorie_balance;
DROP VIEW IF EXISTS facts.daily_calorie_balance;
