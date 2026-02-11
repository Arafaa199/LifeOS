# Location Tracking Contracts

Geofence-based location tracking with known zones, enter/exit events, and zone matching.

## POST /webhook/nexus-location

Ingest a location update from iOS or Home Assistant. Matches against known zones and tracks enter/exit events.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |
| n8n Workflow | `location-webhook.json` |

### Request

```json
{
  "latitude": 25.0782,
  "longitude": 55.1487,
  "location_name": "Gym",
  "event_type": "poll",
  "activity": "stationary",
  "source": "home_assistant"
}
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `latitude` | number | Yes | - | GPS latitude |
| `longitude` | number | Yes | - | GPS longitude |
| `location_name` | string | No | `null` | Optional name from source |
| `event_type` | string | No | `"poll"` | One of: `poll`, `enter`, `exit`, `significant_change` |
| `activity` | string | No | `null` | Motion state (e.g. `stationary`, `walking`, `driving`) |
| `source` | string | No | `"home_assistant"` | One of: `home_assistant`, `ios_app`, `manual` |

### Response

```json
{
  "success": true,
  "location_id": 1234,
  "matched_zones": [
    { "location_id": 1, "name": "gym", "category": "gym", "distance_meters": 12.5 }
  ],
  "enter_events": [
    { "location_id": 1, "name": "gym" }
  ],
  "exit_events": []
}
```

### Processing Pipeline

1. `life.ingest_location()` — stores raw location point
2. `core.process_location_update()` — Haversine matching against `core.known_locations`, creates enter/exit events in `core.location_events`

### Error Responses

| Code | Condition |
|------|-----------|
| `VALIDATION_ERROR` | Missing latitude/longitude |
| `UNAUTHORIZED` | Missing or invalid API key |
| `INTERNAL_ERROR` | Database error |

---

## POST /webhook/nexus-behavioral-event

Log a behavioral event (TV on/off, motion detected, etc.) from Home Assistant automations.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |
| n8n Workflow | `behavioral-event-webhook.json` |

### Request

```json
{
  "event_type": "tv_session_start",
  "source": "home_assistant",
  "metadata": {
    "entity_id": "media_player.samsung_tv"
  }
}
```

---

## Data Model

### core.known_locations

Known zones for geofence matching.

| Column | Type | Description |
|--------|------|-------------|
| `id` | serial | Primary key |
| `name` | text | Zone name (unique) |
| `category` | text | Zone type: `home`, `work`, `gym`, `other` |
| `lat` | double precision | Center latitude |
| `lng` | double precision | Center longitude |
| `radius_meters` | integer | Geofence radius (default 100) |
| `metadata` | jsonb | Extra info |
| `is_active` | boolean | Whether zone is active |

### core.location_events

Enter/exit tracking with duration.

| Column | Type | Description |
|--------|------|-------------|
| `id` | serial | Primary key |
| `location_id` | integer | FK to `core.known_locations` |
| `event_type` | text | `enter` or `exit` |
| `timestamp` | timestamptz | When the event occurred |
| `duration_minutes` | integer | Null on enter, computed on exit |
| `metadata` | jsonb | Extra context |

### core.match_location(lat, lng)

Haversine distance function returning all zones within their radius.

```sql
SELECT * FROM core.match_location(25.0782, 55.1487);
-- Returns: location_id, name, category, distance_meters, radius_meters
```

### core.process_location_update(lat, lng, event_type, location_name)

Processes a location update: matches zones, creates enter events for new zones, exit events for departed zones. Enforces a 5-minute minimum duration to filter drive-by events (migration 191).

---

## Seeded Locations

| Name | Category | Lat | Lng | Radius |
|------|----------|-----|-----|--------|
| gym | gym | 25.07822 | 55.14869 | 150m |

---

## Integration Points

| System | Usage |
|--------|-------|
| Work tracking | `life.v_work_sessions` derives from location_events where category = 'work' |
| BJJ auto-detect | Matches gym zone + time window + WHOOP strain |
| Dashboard | `work_summary` in `dashboard.get_payload()` |
| Explain Today | Work observations in briefing |
| iOS | `LocationTrackingService` sends significant location changes |
| Home Assistant | `rest_command.nexus_log_location` on arrival/departure automations |

### References

| Type | Reference |
|------|-----------|
| DB Schema | `core.known_locations`, `core.location_events` |
| DB Functions | `core.match_location()`, `core.process_location_update()` |
| n8n Workflow | `location-webhook.json`, `behavioral-event-webhook.json` |
| Migrations | `183_geofence_system.up.sql`, `191_geofence_min_duration_bjj_detect.up.sql` |
| iOS Service | `LocationTrackingService.swift` |
