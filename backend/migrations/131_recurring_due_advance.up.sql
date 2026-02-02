-- Migration 131: Recurring item due date auto-advance + fix upcoming view

-- Function to advance recurring items whose next_due_date has passed
CREATE OR REPLACE FUNCTION finance.advance_recurring_due_dates() RETURNS void AS $$
  UPDATE finance.recurring_items
  SET next_due_date = CASE cadence
    WHEN 'daily' THEN next_due_date + INTERVAL '1 day'
    WHEN 'weekly' THEN next_due_date + INTERVAL '1 week'
    WHEN 'biweekly' THEN next_due_date + INTERVAL '2 weeks'
    WHEN 'monthly' THEN next_due_date + INTERVAL '1 month'
    WHEN 'quarterly' THEN next_due_date + INTERVAL '3 months'
    WHEN 'yearly' THEN next_due_date + INTERVAL '1 year'
  END,
  last_occurrence = next_due_date,
  updated_at = NOW()
  WHERE is_active = true AND next_due_date < CURRENT_DATE;
$$ LANGUAGE sql;

-- Fix upcoming_recurring view to include overdue items (not just future)
CREATE OR REPLACE VIEW finance.upcoming_recurring AS
SELECT
    r.*,
    c.name as category_name,
    c.icon as category_icon,
    r.next_due_date - CURRENT_DATE as days_until_due
FROM finance.recurring_items r
LEFT JOIN finance.categories c ON c.id = r.category_id
WHERE r.is_active = true
ORDER BY r.next_due_date;
