-- Rollback Migration 072: Meal Inference Engine

DROP FUNCTION IF EXISTS life.get_pending_meal_confirmations(DATE);
DROP VIEW IF EXISTS life.v_inferred_meals;
DROP TABLE IF EXISTS life.meal_confirmations;
