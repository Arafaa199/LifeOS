# Nexus iOS App

Native iOS app for the Nexus personal life data hub. Log food, water, weight, mood, and more with natural language and voice input.

## Features

### 📊 Dashboard
- Real-time daily summary (calories, protein, water, weight)
- Recent activity log
- Quick stats overview

### ⚡ Quick Log
- Universal natural language input
- Claude interprets what you want to log
- One-tap quick actions for common items
- Voice input support

### 🍽️ Food Logging
- Voice or text input
- **Photo capture** - snap a pic, AI identifies food and estimates nutrition
- Meal type selection (breakfast, lunch, dinner, snack)
- Quick-add buttons for common foods
- Batch meal tracking
- Automatic calorie and macro estimation

### 💧 Water Tracking
- Quick-add presets (250ml, 500ml, custom)
- Daily total tracking
- Widget support (coming soon)

### 📡 Offline Support
- Automatic offline queue when network unavailable
- Pending items indicator on dashboard
- Auto-retry with exponential backoff (max 3 retries)
- Network status bar shows Wi-Fi/Cellular/Offline

### ⚙️ Settings
- Configure webhook URL
- Test connection
- Manage integrations

## Setup

### Prerequisites

1. **Nexus Backend Running**
   - PostgreSQL database
   - n8n with webhooks configured
   - See `/Users/rafa/Cyber/Infrastructure/Nexus-setup/README.md`

2. **Xcode 15+**
   - macOS Sonoma or later
   - iOS 17+ deployment target

### Installation

#### First Time Setup

If the Xcode project doesn't exist yet, see **[XCODE_SETUP.md](XCODE_SETUP.md)** for detailed instructions on creating the Xcode project from source files.

**Quick Steps:**
1. Open Xcode 15+
2. File → New → Project → iOS App
3. Name: `Nexus`, Interface: SwiftUI
4. Add all source files from `Nexus/` directory
5. Configure App Groups capability: `group.com.yourdomain.nexus`
6. Add Siri capability
7. Build and run

#### If Project Exists

1. **Open Project**
   ```bash
   cd /Users/rafa/Cyber/Dev/Nexus-mobile
   open Nexus.xcodeproj
   ```

2. **Configure Signing**
   - Open project in Xcode
   - Select target "Nexus"
   - Go to Signing & Capabilities
   - Select your team
   - Update bundle identifier: `com.yourdomain.nexus`

3. **Configure Webhook URL**
   - Run app
   - Go to Settings tab
   - Enter your n8n webhook base URL (e.g., `https://n8n.rfanw`)
   - Tap "Save Settings"
   - Test connection

### Required n8n Workflows

Ensure these webhooks are configured in n8n:

| Endpoint | Method | Workflow File | Description |
|----------|--------|---------------|-------------|
| `/webhook/nexus-food` | POST | `food-log-webhook.json` | Text-based food logging |
| `/webhook/nexus-water` | POST | `smart-entry-local-first.json` | Water intake logging |
| `/webhook/nexus-weight` | POST | `health-metrics-sync.json` | Weight logging |
| `/webhook/nexus-mood` | POST | `daily-summary-update.json` | Mood/energy logging |
| `/webhook/nexus-universal` | POST | `nexus-universal-webhook.json` | Natural language (any type) |
| `/webhook/nexus-photo-food` | POST | `photo-food-webhook.json` | Photo-based food logging (Claude Vision) |
| `/webhook/nexus-summary` | GET | `daily-summary-fetch.json` | Fetch today's data |

Import from: `/Users/rafa/Cyber/Infrastructure/Nexus-setup/n8n-workflows/`

**Note:** Photo food logging requires multipart/form-data with `photo` (image), `source`, and optional `context` fields.

## Project Structure

```
Nexus/
├── NexusApp.swift              # App entry point
├── Models/
│   └── NexusModels.swift       # Data models & API types
├── Services/
│   ├── NexusAPI.swift          # Network layer + data fetch
│   ├── SpeechRecognizer.swift  # Voice input handler
│   ├── SharedStorage.swift     # App Group data sharing
│   ├── OfflineQueue.swift      # Offline queue with retry
│   ├── NetworkMonitor.swift    # Connectivity monitoring
│   └── PhotoFoodLogger.swift   # Photo capture & upload
├── ViewModels/
│   └── DashboardViewModel.swift
├── Views/
│   ├── ContentView.swift       # Main tab navigation
│   ├── Dashboard/
│   │   └── DashboardView.swift # Summary & recent logs
│   ├── QuickLogView.swift      # Universal quick logging
│   ├── Food/
│   │   └── FoodLogView.swift   # Detailed food + photo logging
│   └── SettingsView.swift      # App configuration
├── Widgets/
│   ├── NexusWidgets.swift      # Widget bundle & definitions
│   ├── InteractiveWaterWidget.swift  # Interactive water logging
│   └── WidgetIntents.swift     # App Intents for Siri & widgets
└── Info.plist
```

## Usage

### Quick Log (Fastest)

1. Open app → Quick Log tab
2. Speak or type naturally:
   - "2 eggs for breakfast"
   - "500ml water"
   - "weight 75kg"
   - "mood 7, energy 6"
3. Tap "Log It"

### Food Logging (Detailed)

1. Open app → Food tab
2. Select meal type
3. Describe what you ate (or use voice)
4. Tap "Log Food"

### Voice Input

Tap the microphone icon on any input screen to use voice dictation.

## Siri Integration & App Shortcuts

The app includes built-in App Shortcuts (iOS 17+) that allow Siri to trigger logging:

**Available Shortcuts:**
- "Hey Siri, log water in Nexus"
- "Hey Siri, log food in Nexus"
- "Hey Siri, log to Nexus [anything]"

**Setup:**
1. Open Settings → Siri & Search → Nexus
2. Enable "Learn from this App"
3. Suggested shortcuts will appear automatically

**Custom Shortcuts:**
1. Open Shortcuts app
2. Tap "+" to create new shortcut
3. Add "Run App Intent" action
4. Select Nexus → Log Water/Food/Universal
5. Configure parameters and add to Home Screen

## Widgets

Nexus includes multiple widget types for quick access:

### Water Logger Widget (Small/Medium)
- **Small**: Shows today's water total + quick 250ml button
- **Medium**: Shows total + three quick buttons (250ml, 500ml, 1L)
- Tap buttons to log water without opening the app (iOS 17+)

### Daily Summary Widget (Medium/Large)
- **Medium**: Compact view of calories, protein, water, weight
- **Large**: Detailed stats with labels and icons

### Adding Widgets:
1. Long press on Home Screen
2. Tap "+" in top left
3. Search for "Nexus"
4. Choose widget type and size
5. Drag to Home Screen
6. Configure if needed

**Note:** Widgets require App Groups capability to share data. See WIDGET_SETUP.md for Xcode configuration.

## Troubleshooting

### Connection Failed

1. Check webhook URL in Settings
2. Ensure n8n is running: `ssh pivpn "docker ps | grep n8n"`
3. Test webhook manually:
   ```bash
   curl -X POST https://n8n.rfanw/webhook/nexus-universal \
     -H "Content-Type: application/json" \
     -d '{"text":"test","source":"curl"}'
   ```

### Speech Recognition Not Working

1. Go to Settings → Privacy → Speech Recognition
2. Enable for Nexus app
3. Grant microphone access

### Missing Data on Dashboard

Dashboard shows data logged during current app session. For full history, future versions will query the database directly.

## Development

### Adding a New Log Type

1. Add request model to `NexusModels.swift`
2. Add API method to `NexusAPI.swift`
3. Create view in `Views/`
4. Update `ContentView.swift` to include new tab

### Testing

```bash
# Run tests
xcodebuild test -scheme Nexus -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

## API Reference

### POST /webhook/nexus-universal

Universal endpoint that accepts natural language.

**Request:**
```json
{
  "text": "2 eggs for breakfast",
  "source": "ios",
  "context": "auto"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Logged breakfast: 2 eggs",
  "data": {
    "calories": 140,
    "protein": 12.0
  }
}
```

### Other Endpoints

See `/Users/rafa/Cyber/Infrastructure/Nexus-setup/n8n-workflows/README.md`

## Roadmap

- [x] iOS Widgets
- [x] Siri Shortcuts integration (App Intents)
- [x] Voice input for logging
- [x] Offline mode with sync (automatic queue + retry)
- [x] Photo food logging (Claude Vision)
- [x] Network status indicator
- [ ] Apple Watch app
- [ ] Batch meal management
- [ ] Custom quick actions configuration
- [ ] Dark mode (automatic - follows system)
- [ ] iPad optimization
- [ ] Lock Screen widgets (iOS 16+)
- [ ] Live Activities for active logging sessions
- [ ] macOS app (Catalyst)

## Related Projects

- **Backend**: `/Users/rafa/Cyber/Infrastructure/Nexus-setup/`
- **MCP Server**: `/Users/rafa/Cyber/Infrastructure/Nexus-setup/mcp-server/`
- **iOS Shortcuts**: `/Users/rafa/Cyber/Infrastructure/Nexus-setup/ios-shortcuts/`

## License

Private use only.

## Documentation

- **[XCODE_SETUP.md](XCODE_SETUP.md)** - Complete guide to creating the Xcode project
- **[WIDGET_SETUP.md](WIDGET_SETUP.md)** - Detailed widget and App Intent configuration
- **[README.md](README.md)** - This file: app overview, features, and usage

## Support

For issues or questions, see main Nexus documentation or check n8n workflow logs.
