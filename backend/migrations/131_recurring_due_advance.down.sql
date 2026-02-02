DROP FUNCTION IF EXISTS finance.advance_recurring_due_dates();

-- Restore original view with future-only filter
CREATE OR REPLACE VIEW finance.upcoming_recurring AS
SELECT
    r.*,
    c.name as category_name,
    c.icon as category_icon,
    r.next_due_date - CURRENT_DATE as days_until_due
FROM finance.recurring_items r
LEFT JOIN finance.categories c ON c.id = r.category_id
WHERE r.is_active = true
AND r.next_due_date >= CURRENT_DATE
ORDER BY r.next_due_date;
