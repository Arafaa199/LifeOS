# Home Automation Contracts

Home Assistant integration via n8n webhooks.

## GET /webhook/nexus-home-status

Fetches Home Assistant device states.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |

### Response

```json
{
  "success": true,
  "home": {
    "lights": {
      "lightstrip": {
        "entity_id": "light.hue_lightstrip_plus_1",
        "state": "on",
        "brightness": 192,
        "brightness_pct": 75
      }
    },
    "switches": {
      "left_monitor": {
        "entity_id": "switch.leftmonplug_socket_1",
        "state": "on"
      },
      "right_monitor": {
        "entity_id": "switch.rightmonplug_socket_1",
        "state": "off"
      },
      "printer": {
        "entity_id": "switch.3d_printer_socket_1",
        "state": "off"
      }
    },
    "vacuum": {
      "entity_id": "vacuum.vacuum",
      "state": "docked",
      "battery": 100,
      "fan_speed": "standard"
    },
    "camera": {
      "entity_id": "camera.ezviz_camera",
      "state": "idle",
      "sleeping": false
    },
    "presence": {
      "home": true,
      "last_motion": "2026-02-08T11:30:00Z",
      "motion_location": "living_room"
    }
  },
  "last_updated": "2026-02-08T12:00:00Z"
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `HomeModels.swift` → `HomeStatusResponse`, `HomeStatus` |
| n8n Workflow | `home-status-webhook.json` |
| DB Table | N/A (real-time from Home Assistant) |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-home-control

Controls a Home Assistant device.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "action": "toggle",
  "entity_id": "light.hue_lightstrip_plus_1",
  "data": {
    "brightness": 50
  }
}
```

### Actions

| Action | Description | Applicable To |
|--------|-------------|---------------|
| `toggle` | Toggle on/off | lights, switches |
| `turn_on` | Turn on | lights, switches |
| `turn_off` | Turn off | lights, switches |
| `start` | Start cleaning | vacuum |
| `stop` | Stop cleaning | vacuum |
| `return` | Return to base | vacuum |
| `locate` | Locate (beep) | vacuum |

### Response

```json
{
  "success": true,
  "entity_id": "light.hue_lightstrip_plus_1",
  "new_state": "on",
  "logged": true
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `HomeModels.swift` → `HomeControlRequest`, `HomeControlResponse`, `HomeAction` |
| n8n Workflow | `home-control-webhook.json` |
| DB Table | `raw.home_events` (logged) |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `NOT_FOUND`, `INTERNAL_ERROR`

---

## Device Entity IDs

| Device | Entity ID |
|--------|-----------|
| Hue Lightstrip | `light.hue_lightstrip_plus_1` |
| Left Monitor | `switch.leftmonplug_socket_1` |
| Right Monitor | `switch.rightmonplug_socket_1` |
| 3D Printer | `switch.3d_printer_socket_1` |
| Vacuum | `vacuum.vacuum` |
| Camera | `camera.ezviz_camera` |
| Motion Sensor | `binary_sensor.hue_motion_sensor_1_motion` |

---

## iOS Integration

The iOS app provides read-only status display with an "Open Home Assistant" button:

```swift
// HomeViewModel.swift
func openHomeAssistant() {
    // Try HA Companion app first
    if UIApplication.shared.canOpenURL(URL(string: "homeassistant://")!) {
        UIApplication.shared.open(URL(string: "homeassistant://")!)
    } else {
        // Fallback to web UI
        UIApplication.shared.open(URL(string: "https://ha.rfanw")!)
    }
}
```

Device control is delegated to the Home Assistant app for reliability.
