-- Migration Rollback: Drop Grocery → Nutrition View
-- Date: 2026-01-25

DROP VIEW IF EXISTS nutrition.v_grocery_nutrition;
