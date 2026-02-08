# Music Contracts

Apple Music listening event tracking.

## POST /webhook/nexus-music-events

Logs music listening events.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "events": [
    {
      "session_id": "uuid-v4",
      "track_title": "Bohemian Rhapsody",
      "artist": "Queen",
      "album": "A Night at the Opera",
      "duration_sec": 354,
      "apple_music_id": "12345",
      "started_at": "2026-02-08T10:00:00Z",
      "ended_at": "2026-02-08T10:05:54Z",
      "source": "apple_music"
    }
  ]
}
```

### Response

```json
{
  "success": true,
  "message": "2 events logged"
}
```

### Idempotency

Deduplicated by `(session_id, started_at)`.

### References

| Type | Reference |
|------|-----------|
| iOS Model | `MusicModels.swift` → `MusicEventsRequest`, `ListeningEvent` |
| n8n Workflow | `music-listening-webhook.json` |
| DB Table | `life.listening_events` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `CONFLICT`, `INTERNAL_ERROR`

---

## GET /webhook/nexus-music-history

Fetches recent listening history.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |
| Query Params | `limit` (default 10) |

### Response

```json
{
  "success": true,
  "events": [
    {
      "id": 1,
      "session_id": "uuid-v4",
      "track_title": "Bohemian Rhapsody",
      "artist": "Queen",
      "album": "A Night at the Opera",
      "duration_sec": 354,
      "apple_music_id": "12345",
      "started_at": "2026-02-08T10:00:00Z",
      "ended_at": "2026-02-08T10:05:54Z",
      "source": "apple_music"
    }
  ]
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `MusicModels.swift` → `MusicHistoryResponse`, `ListeningEvent` |
| n8n Workflow | `music-listening-webhook.json` |
| DB Table | `life.listening_events` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## iOS Integration

Music logging is passive and runs behind a feature flag:

```swift
// In Settings
@AppStorage("enableMusicLogging") var enableMusicLogging = false
```

When enabled, `MusicService` observes Apple Music playback:
- Creates a session when playback starts
- Logs track changes with timestamps
- Batches events and sends to webhook every 30 seconds
- Persists pending events to UserDefaults for reliability

## Dashboard Integration

Music stats appear in dashboard:

```json
{
  "music_today": {
    "tracks_played": 15,
    "total_minutes": 45,
    "unique_artists": 8,
    "top_artist": "Queen",
    "top_album": "Greatest Hits"
  }
}
```
