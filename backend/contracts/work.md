# Work Hour Tracking Contracts

Work sessions derived from geofence enter/exit events at locations with `category = 'work'`.

## Data Model

Work sessions are **not a separate table** — they are derived from `core.location_events` via the `life.v_work_sessions` view.

```
core.location_events (enter/exit) → life.v_work_sessions (view) → life.get_work_summary() → dashboard
```

### life.v_work_sessions View

| Column | Type | Description |
|--------|------|-------------|
| `id` | integer | Enter event ID |
| `location_id` | integer | Reference to `core.known_locations` |
| `location_name` | text | Location name |
| `clock_in` | timestamptz | Enter event timestamp |
| `clock_out` | timestamptz | Exit event timestamp (null if still at work) |
| `duration_minutes` | integer | Duration from exit event (null if still at work) |
| `work_date` | date | Dubai-timezone date of the enter event |

---

## life.get_work_summary(for_date)

Returns a JSONB summary of work activity for a given date. Used by `dashboard.get_payload()`.

### Parameters

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `for_date` | date | `life.dubai_today()` | Date to summarize |

### Response (JSONB)

```json
{
  "work_date": "2026-02-09",
  "total_minutes": 480,
  "total_hours": 8.0,
  "sessions": 1,
  "first_arrival": "2026-02-09T05:00:00Z",
  "last_departure": "2026-02-09T13:00:00Z",
  "is_at_work": false,
  "current_session_start": null
}
```

Returns `NULL` if no work activity for the date.

### Field Definitions

| Field | Type | Description |
|-------|------|-------------|
| `work_date` | string | Date (YYYY-MM-DD) |
| `total_minutes` | integer | Sum of all session durations (includes open session elapsed) |
| `total_hours` | number | `total_minutes / 60`, rounded to 1 decimal |
| `sessions` | integer | Number of work sessions (completed + open) |
| `first_arrival` | string | Earliest clock-in timestamp |
| `last_departure` | string | Latest clock-out timestamp (null if still at work) |
| `is_at_work` | boolean | True if there's an open enter event with no matching exit |
| `current_session_start` | string | Start time of open session (null if not at work) |

---

## Dashboard Integration

Work summary appears in `dashboard.get_payload()` as `work_summary` (schema v19, migration 184).

Also adds work observations to `explain_today` briefing:
- At work > 9h: priority 7 ("Long day")
- At work > 8h: priority 5 ("Full day")
- At work < 8h: priority 3 ("At work")
- Completed > 9h: priority 6 ("Long work day")
- Completed > 8h: priority 4 (hours logged)

### References

| Type | Reference |
|------|-----------|
| DB View | `life.v_work_sessions` |
| DB Function | `life.get_work_summary()` |
| Dashboard | `dashboard.get_payload()` → `work_summary` |
| Briefing | `life.explain_today()` → work section |
| Migration | `184_work_hour_tracking.up.sql` |
| Depends On | `core.location_events`, `core.known_locations` (category = 'work') |
