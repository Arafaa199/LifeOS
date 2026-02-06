-- Home Assistant device control event logging
-- Tracks all device toggles for correlation analysis

CREATE TABLE IF NOT EXISTS life.home_events (
    id              SERIAL PRIMARY KEY,
    event_at        TIMESTAMPTZ DEFAULT NOW(),
    entity_id       TEXT NOT NULL,
    action          TEXT NOT NULL,  -- 'toggle', 'turn_on', 'turn_off', 'start', 'return'
    old_state       TEXT,
    new_state       TEXT,
    source          TEXT DEFAULT 'ios',  -- 'ios', 'ha_automation', 'voice', 'widget'
    scene_name      TEXT,
    metadata        JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_home_events_at ON life.home_events (event_at DESC);
CREATE INDEX idx_home_events_entity ON life.home_events (entity_id);
CREATE INDEX idx_home_events_day ON life.home_events ((event_at::date));

COMMENT ON TABLE life.home_events IS 'Logs all Home Assistant device control actions from iOS app';

GRANT SELECT, INSERT ON life.home_events TO nexus;
GRANT USAGE, SELECT ON SEQUENCE life.home_events_id_seq TO nexus;
