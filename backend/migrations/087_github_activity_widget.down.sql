-- Down migration 087: Remove GitHub Activity Widget
DROP VIEW IF EXISTS life.v_github_activity_widget;
DROP FUNCTION IF EXISTS life.get_github_activity_widget(INTEGER);
