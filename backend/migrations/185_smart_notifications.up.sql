BEGIN;

-- Smart Notifications dedup table
-- Prevents duplicate notifications by tracking (type, date) pairs
CREATE TABLE IF NOT EXISTS core.notification_log (
    id SERIAL PRIMARY KEY,
    notification_type TEXT NOT NULL,
    sent_date DATE NOT NULL,
    sent_at TIMESTAMPTZ DEFAULT NOW(),
    message TEXT,
    UNIQUE(notification_type, sent_date)
);

CREATE INDEX idx_notification_log_date ON core.notification_log (sent_date DESC);

INSERT INTO ops.schema_migrations (filename) VALUES ('185_smart_notifications.up.sql');

COMMIT;
