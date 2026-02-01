-- Migration 102: Reminders schema
-- Stores iOS Reminders (EventKit) synced via n8n webhook

CREATE TABLE IF NOT EXISTS raw.reminders (
    id SERIAL PRIMARY KEY,
    reminder_id VARCHAR(255) NOT NULL,
    title VARCHAR(500),
    notes TEXT,
    due_date TIMESTAMPTZ,
    is_completed BOOLEAN DEFAULT false,
    completed_date TIMESTAMPTZ,
    priority INT DEFAULT 0,
    list_name VARCHAR(255),
    source VARCHAR(50) DEFAULT 'ios_eventkit',
    client_id UUID,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_reminders_reminder_id_source UNIQUE (reminder_id, source)
);

CREATE INDEX idx_reminders_due_date ON raw.reminders (due_date) WHERE due_date IS NOT NULL;
CREATE INDEX idx_reminders_list_name ON raw.reminders (list_name);
CREATE INDEX idx_reminders_completed ON raw.reminders (is_completed);
