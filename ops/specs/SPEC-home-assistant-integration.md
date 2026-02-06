# Home Assistant Integration for Nexus iOS App

## Overview

Bring smart home control and status into the Nexus app, creating a unified life dashboard that includes home automation alongside health, finance, and productivity data.

---

## Current State

### What Exists
- **HA → n8n → Nexus DB**: One-way data flow
  - Location arrival/departure events
  - Behavioral events (sleep/wake detection, TV sessions)
  - WHOOP sync via HA sensors
  - Weight from Eufy scale

### HA Entities Available
| Category | Entities |
|----------|----------|
| **Switches** | `switch.leftmonplug_socket_1`, `switch.rightmonplug_socket_1`, `switch.3d_printer_socket_1` |
| **Lights** | `light.hue_lightstrip_plus_1` |
| **Sensors** | `sensor.whoop_*`, `sensor.3d_printer_*`, motion sensors |
| **Vacuum** | `vacuum.vacuum` (Eufy X10), `sensor.vacuum_battery`, `button.vacuum_wash_mop` |
| **Camera** | `camera.ezviz_camera`, `switch.ezviz_camera_sleep` |
| **Input Booleans** | `input_boolean.living_room_lights_manual_off`, `input_boolean.screens` |

### What's Missing
- iOS app cannot view HA entity states
- iOS app cannot control HA devices
- No home status in dashboard
- No cross-integration (e.g., "low recovery → suggest home office mode")

---

## Architecture Options

### Option A: Direct HA API (Not Recommended)
```
iOS App → HA REST API (port 8123)
```
**Cons:** Requires exposing HA externally, auth token management, no logging

### Option B: n8n as Proxy (Recommended)
```
iOS App → n8n webhooks → HA REST API → n8n → iOS App
```
**Pros:**
- All traffic through existing n8n infrastructure
- Logging and error handling in n8n
- Can add business logic (e.g., log device toggles to Nexus DB)
- Auth handled by n8n credential

### Option C: WebSocket (Future)
```
iOS App ↔ HA WebSocket → Real-time updates
```
**Cons:** Complex, requires persistent connection

**Decision: Option B** - n8n proxy for MVP, consider WebSocket for v2.

---

## Feature Specification

### 1. Home Status Card (Dashboard)

**Location:** TodayView, below StateCardView

**Design:**
```
┌─────────────────────────────────────────┐
│  🏠 Home                    [>]         │
├─────────────────────────────────────────┤
│                                         │
│  🟢 Lights     🔴 Monitors    🟢 Printer │
│     On            Off           Idle    │
│                                         │
│  🤖 Vacuum: Docked (87%)                │
│  📹 Camera: Active                      │
│                                         │
└─────────────────────────────────────────┘
```

**Data Required:**
```json
{
  "lights": {"state": "on", "brightness": 80},
  "monitors": {"state": "off"},
  "printer": {"state": "idle", "progress": null},
  "vacuum": {"state": "docked", "battery": 87},
  "camera": {"state": "active", "sleeping": false}
}
```

### 2. Home Control View (Dedicated Screen)

**Access:** Tap Home card → Full screen control

**Design:**
```
┌─────────────────────────────────────────┐
│  ← Home Control                         │
├─────────────────────────────────────────┤
│                                         │
│  LIGHTS                                 │
│  ┌───────────────────────────────────┐  │
│  │ 💡 Hue Lightstrip                 │  │
│  │ ○───────────●──────○  80%    [ON] │  │
│  └───────────────────────────────────┘  │
│                                         │
│  OFFICE                                 │
│  ┌───────────────────────────────────┐  │
│  │ 🖥️ Left Monitor          [OFF]   │  │
│  │ 🖥️ Right Monitor         [OFF]   │  │
│  │ 🖨️ 3D Printer            [OFF]   │  │
│  └───────────────────────────────────┘  │
│                                         │
│  CLEANING                               │
│  ┌───────────────────────────────────┐  │
│  │ 🤖 Eufy X10 Pro                   │  │
│  │ Status: Docked  Battery: 87%      │  │
│  │ [Start Clean] [Return] [Wash Mop] │  │
│  └───────────────────────────────────┘  │
│                                         │
│  SECURITY                               │
│  ┌───────────────────────────────────┐  │
│  │ 📹 EZVIZ Camera                   │  │
│  │ [Preview]     Sleep: [OFF]        │  │
│  └───────────────────────────────────┘  │
│                                         │
│  SCENES                                 │
│  ┌───────────────────────────────────┐  │
│  │ [🌙 Bedtime] [💼 Work] [🎬 Movie] │  │
│  └───────────────────────────────────┘  │
│                                         │
└─────────────────────────────────────────┘
```

### 3. Quick Actions (Widgets + Shortcuts)

**Widget:** "Home Quick Actions" (2x2)
- 4 toggles: Lights, Monitors, Camera, Vacuum
- Tap to toggle, long-press for more options

**3D Touch / Long Press App Icon:**
- "Turn off all lights"
- "Start vacuum"
- "Work mode" (turns on monitors)

### 4. Contextual Automations

**Recovery-Based:**
- Low recovery (<50%) → Suggest "Work from home mode"
- High recovery (>80%) → No suggestions

**Time-Based:**
- Evening (after 10 PM) → "Bedtime mode available"
- Morning (alarm or motion) → Auto-fetch home status

**Location-Based:**
- Leave home → Auto-switch camera to active
- Arrive home → Lights on if dark outside

---

## n8n Webhook Specifications

### GET `/webhook/nexus-home-status`

Fetches current state of all monitored devices.

**n8n Flow:**
```
Webhook → HA API (get states) → Transform → Respond
```

**HA API Call:**
```
POST http://172.17.0.1:8123/api/states
Headers: Authorization: Bearer <token>
```

**Response:**
```json
{
  "success": true,
  "home": {
    "lights": {
      "hue_lightstrip": {
        "entity_id": "light.hue_lightstrip_plus_1",
        "state": "on",
        "brightness": 204,
        "brightness_pct": 80
      }
    },
    "switches": {
      "left_monitor": {"entity_id": "switch.leftmonplug_socket_1", "state": "off"},
      "right_monitor": {"entity_id": "switch.rightmonplug_socket_1", "state": "off"},
      "printer": {"entity_id": "switch.3d_printer_socket_1", "state": "off"}
    },
    "vacuum": {
      "entity_id": "vacuum.vacuum",
      "state": "docked",
      "battery": 87,
      "fan_speed": "standard"
    },
    "camera": {
      "entity_id": "camera.ezviz_camera",
      "state": "idle",
      "sleeping": false
    },
    "presence": {
      "home": true,
      "last_motion": "2026-02-06T14:32:00+04:00",
      "motion_location": "living_room"
    }
  },
  "last_updated": "2026-02-06T14:35:00+04:00"
}
```

### POST `/webhook/nexus-home-control`

Controls a device or triggers a scene.

**Request:**
```json
{
  "action": "toggle" | "turn_on" | "turn_off" | "set" | "scene",
  "entity_id": "switch.leftmonplug_socket_1",
  "data": {
    "brightness": 80  // optional, for lights
  }
}
```

**n8n Flow:**
```
Webhook → Validate → HA API (call service) → Log to Nexus DB → Respond
```

**HA API Calls:**
- Toggle: `POST /api/services/homeassistant/toggle`
- Turn On: `POST /api/services/switch/turn_on` or `light/turn_on`
- Scene: `POST /api/services/scene/turn_on`

**Response:**
```json
{
  "success": true,
  "entity_id": "switch.leftmonplug_socket_1",
  "new_state": "on",
  "logged": true
}
```

### POST `/webhook/nexus-home-scene`

Triggers a scene or automation.

**Request:**
```json
{
  "scene": "bedtime" | "work" | "movie" | "away"
}
```

**Scenes Definition (in n8n or HA):**

| Scene | Actions |
|-------|---------|
| `bedtime` | Lights off, monitors off, camera active |
| `work` | Monitors on, lights to 60%, camera sleep |
| `movie` | Lights to 20%, monitors off |
| `away` | All off, camera active, vacuum start |

---

## Database Logging

**New table: `life.home_events`**

```sql
CREATE TABLE life.home_events (
    id              SERIAL PRIMARY KEY,
    event_at        TIMESTAMPTZ DEFAULT NOW(),
    entity_id       TEXT NOT NULL,
    action          TEXT NOT NULL,  -- 'toggle', 'turn_on', 'turn_off', 'scene'
    old_state       TEXT,
    new_state       TEXT,
    source          TEXT DEFAULT 'ios',  -- 'ios', 'ha_automation', 'voice'
    scene_name      TEXT,
    metadata        JSONB
);

CREATE INDEX idx_home_events_at ON life.home_events (event_at DESC);
CREATE INDEX idx_home_events_entity ON life.home_events (entity_id);

GRANT SELECT, INSERT ON life.home_events TO nexus;
GRANT USAGE, SELECT ON SEQUENCE life.home_events_id_seq TO nexus;
```

**Use Cases:**
- "How often do I use the vacuum?"
- "Average time monitors are on per day"
- "Correlation between lights-off time and sleep quality"

---

## iOS Implementation

### New Files

| File | Purpose |
|------|---------|
| `ios/Nexus/Views/Home/HomeStatusCard.swift` | Dashboard card |
| `ios/Nexus/Views/Home/HomeControlView.swift` | Full control screen |
| `ios/Nexus/Views/Home/DeviceRow.swift` | Reusable device toggle row |
| `ios/Nexus/Views/Home/SceneButton.swift` | Scene trigger button |
| `ios/Nexus/Models/HomeModels.swift` | Data models |
| `ios/Nexus/ViewModels/HomeViewModel.swift` | State management |

### Modified Files

| File | Change |
|------|--------|
| `ios/Nexus/Views/Dashboard/TodayView.swift` | Add HomeStatusCard |
| `ios/Nexus/Views/MoreView.swift` | Add Home nav link |
| `ios/Nexus/Services/NexusAPI.swift` | Add home endpoints |
| `ios/Nexus/Models/DashboardPayload.swift` | Add home status to payload |

### Models

```swift
struct HomeStatus: Codable {
    let lights: [String: LightState]
    let switches: [String: SwitchState]
    let vacuum: VacuumState?
    let camera: CameraState?
    let presence: PresenceState?
    let lastUpdated: Date
}

struct LightState: Codable {
    let entityId: String
    let state: String  // "on", "off", "unavailable"
    let brightness: Int?
    let brightnessPct: Int?
}

struct SwitchState: Codable {
    let entityId: String
    let state: String
}

struct VacuumState: Codable {
    let entityId: String
    let state: String  // "docked", "cleaning", "returning", "error"
    let battery: Int
    let fanSpeed: String?
}

struct CameraState: Codable {
    let entityId: String
    let state: String
    let sleeping: Bool
}

struct PresenceState: Codable {
    let home: Bool
    let lastMotion: Date?
    let motionLocation: String?
}
```

### API Methods

```swift
extension NexusAPI {
    func fetchHomeStatus() async throws -> HomeStatusResponse {
        return try await get("/webhook/nexus-home-status")
    }

    func controlDevice(entityId: String, action: HomeAction, data: [String: Any]? = nil) async throws -> HomeControlResponse {
        let request = HomeControlRequest(action: action, entityId: entityId, data: data)
        return try await post("/webhook/nexus-home-control", body: request)
    }

    func triggerScene(_ scene: String) async throws -> HomeControlResponse {
        let request = HomeSceneRequest(scene: scene)
        return try await post("/webhook/nexus-home-scene", body: request)
    }
}

enum HomeAction: String, Codable {
    case toggle, turnOn = "turn_on", turnOff = "turn_off", set
}
```

---

## Widget: Home Quick Actions

**Widget file:** `ios/NexusWidgets/HomeQuickActionsWidget.swift`

**Design (2x2):**
```
┌─────────────────────────────────────────┐
│  💡        🖥️        🤖        📹       │
│ Lights   Monitors  Vacuum   Camera     │
│  ON        OFF     Docked    Active    │
└─────────────────────────────────────────┘
```

**Interactions:**
- Tap icon → Toggle device
- Uses App Intents for background execution

---

## Security Considerations

1. **API Key:** All n8n webhooks require `X-API-Key` header
2. **Rate Limiting:** Limit control actions to 10/minute per device
3. **Logging:** All control actions logged to `life.home_events`
4. **Sensitive Entities:** Camera controls require confirmation dialog

---

## Implementation Phases

### Phase 1: Read-Only Status (1 session)
1. n8n webhook: GET home status
2. iOS: HomeStatusCard on TodayView
3. iOS: HomeViewModel with polling (every 30s when visible)

### Phase 2: Device Control (1-2 sessions)
1. n8n webhook: POST home control
2. iOS: HomeControlView with toggles
3. Database: `life.home_events` logging

### Phase 3: Scenes & Widgets (1 session)
1. n8n webhook: POST scene trigger
2. iOS: Scene buttons
3. Widget: Home Quick Actions

### Phase 4: Contextual Integration (1 session)
1. Add home status to dashboard payload
2. Recovery-based suggestions
3. Evening review: "Lights off at X time"

---

## Open Questions

1. Should camera preview be in-app or deep-link to HA app?
2. Include 3D printer detailed status (temps, progress)?
3. Add Siri Shortcuts for scenes?
4. Real-time updates via WebSocket or polling sufficient?

---

## Success Metrics

1. **Adoption:** Home card visible on dashboard within 1 week
2. **Usage:** >5 device controls/day via app (vs HA app or voice)
3. **Insight:** At least 1 correlation discovered (e.g., late lights → poor sleep)
4. **Convenience:** User prefers Nexus for quick toggles over HA app
