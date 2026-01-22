# Smart Buttons for Nexus

Physical buttons for one-press logging. No phone needed.

## Options

### 1. Flic Buttons (~$30 each)
- Connect to phone/hub via Bluetooth
- Trigger iOS Shortcuts or HTTP requests
- Single, double, hold = 3 actions per button

### 2. IKEA TRÅDFRI Shortcut Button (~$10)
- Works with Home Assistant
- Zigbee - needs coordinator
- Single, double, hold actions

### 3. Aqara Mini Switch (~$15)
- Zigbee - works with HA
- Single, double, long, shake actions
- Very small, can stick anywhere

### 4. ESP32 DIY Button (~$5)
- Custom build with ESPHome
- WiFi direct to n8n
- Multiple buttons on one board

## Recommended Setup

### Kitchen - Water Station
**Button**: Aqara Mini on fridge or water filter

| Action | What it does |
|--------|-------------|
| Single press | Log 1 glass (250ml) |
| Double press | Log 2 glasses |
| Long press | Log full bottle (500ml) |

**HA Automation**:
```yaml
automation:
  - alias: "Nexus: Water button"
    trigger:
      - platform: event
        event_type: zha_event
        event_data:
          device_id: !input button_device
    action:
      - choose:
          - conditions: "{{ trigger.event.data.command == 'single' }}"
            sequence:
              - service: rest_command.nexus_water
                data:
                  amount: 250
          - conditions: "{{ trigger.event.data.command == 'double' }}"
            sequence:
              - service: rest_command.nexus_water
                data:
                  amount: 500
```

### Bathroom - Weight Station
**Button**: Next to scale (or scale has button)

| Action | What it does |
|--------|-------------|
| Press after weighing | Confirms weight logged (scale auto-sends) |
| Double press | Skip today's weight |

### Bedroom - Morning/Night Routine
**Button**: Bedside table

| Action | What it does |
|--------|-------------|
| Single (morning) | Mark "morning routine" complete |
| Single (night) | Trigger mood check prompt on phone |
| Double | Mark meditation done |

### Office - Supplement Station
**Button**: Next to supplement shelf

| Action | What it does |
|--------|-------------|
| Press | Log "morning supplements" taken |
| Double | Log "evening supplements" taken |

## HA REST Commands

Add to `configuration.yaml`:

```yaml
rest_command:
  nexus_water:
    url: "http://n8n:5678/webhook/nexus"
    method: POST
    content_type: "application/json"
    payload: '{"text": "{{ amount }}ml water", "source": "button"}'

  nexus_habit:
    url: "http://n8n:5678/webhook/nexus"
    method: POST
    content_type: "application/json"
    payload: '{"text": "done {{ habit }}", "source": "button"}'

  nexus_supplement:
    url: "http://n8n:5678/webhook/nexus"
    method: POST
    content_type: "application/json"
    payload: '{"text": "took {{ which }} supplements", "source": "button"}'
```

## ESP32 Multi-Button Panel

Build a custom panel with 4-6 buttons for kitchen:

```yaml
# ESPHome config
esphome:
  name: nexus-buttons
  platform: ESP32
  board: esp32dev

wifi:
  ssid: !secret wifi_ssid
  password: !secret wifi_password

binary_sensor:
  - platform: gpio
    pin: GPIO12
    name: "Water Button"
    on_press:
      - http_request.post:
          url: http://n8n:5678/webhook/nexus
          json:
            text: "water"
            source: "esp_button"

  - platform: gpio
    pin: GPIO14
    name: "Coffee Button"
    on_press:
      - http_request.post:
          url: http://n8n:5678/webhook/nexus
          json:
            text: "coffee"
            source: "esp_button"

  - platform: gpio
    pin: GPIO27
    name: "Snack Button"
    on_press:
      # Opens a prompt for what snack
      - homeassistant.service:
          service: notify.mobile_app_iphone
          data:
            message: "What snack?"
            data:
              actions:
                - action: "SNACK_FRUIT"
                  title: "Fruit"
                - action: "SNACK_NUTS"
                  title: "Nuts"
                - action: "SNACK_OTHER"
                  title: "Other..."
```

## Button Label Ideas

Use a label maker or small e-ink display:

```
[💧 Water]  [☕ Coffee]  [🍌 Fruit]  [💊 Supps]
```

Or LED indicators that show daily progress:
- Water: LED strip showing 0-8 glasses
- Changes color when goal reached
