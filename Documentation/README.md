# Nexus iOS App - Development Guide

## Quick Start

```bash
cd /Users/rafa/Cyber/Dev/Nexus-mobile
open Nexus.xcodeproj
# Cmd+B to build, Cmd+R to run
```

## Project Structure

```
Nexus/
├── NexusApp.swift              # App entry point
├── Models/
│   ├── NexusModels.swift       # Core data models
│   └── FinanceModels.swift     # Finance types
├── Services/
│   ├── NexusAPI.swift          # Network layer
│   ├── HealthKitManager.swift  # Apple Health integration
│   ├── SpeechRecognizer.swift  # Voice input
│   ├── OfflineQueue.swift      # Offline queue with retry
│   └── NetworkMonitor.swift    # Connectivity monitoring
├── ViewModels/
│   ├── DashboardViewModel.swift
│   └── FinanceViewModel.swift
├── Views/
│   ├── ContentView.swift       # Tab navigation
│   ├── Dashboard/DashboardView.swift
│   ├── Finance/FinanceView.swift
│   ├── Food/FoodLogView.swift
│   └── SettingsView.swift
└── Nexus.entitlements          # HealthKit capability
```

## Key Features

| Feature | Files | Backend Webhook |
|---------|-------|-----------------|
| Food Logging | `FoodLogView.swift` | `POST /webhook/nexus-food` |
| Finance | `FinanceView.swift`, `FinanceViewModel.swift` | `POST /webhook/nexus-expense` |
| Health (WHOOP) | `DashboardView.swift` | `GET /webhook/nexus-sleep` |
| Health (HealthKit) | `HealthKitManager.swift` | `POST /webhook/nexus-weight` |
| Offline Queue | `OfflineQueue.swift` | Auto-retry on reconnect |

## HealthKit Integration

The app reads from Apple Health (Eufy scale, Apple Watch):
- **Weight**: Synced to backend via `/webhook/nexus-weight`
- **Steps/Calories**: Displayed locally only
- **WHOOP data**: Fetched from backend (synced via Home Assistant)

**Capability**: `Nexus.entitlements` has HealthKit enabled.

## Build Requirements

- Xcode 15+
- iOS 17+ deployment target
- Signing team configured

## Troubleshooting

### Build Fails
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData
# Then Cmd+Shift+K (clean) and Cmd+B (build)
```

### API Connection Failed
1. Check webhook URL in Settings tab
2. Verify n8n running: `ssh pivpn "docker ps | grep n8n"`
3. Test: `curl https://n8n.rfanw/webhook/nexus-summary`

### HealthKit Not Working
1. Settings > Privacy > Health > Nexus > Enable all
2. Ensure `Nexus.entitlements` has `com.apple.developer.healthkit`

## Backend Integration

**n8n Workflows**: `~/Cyber/Infrastructure/Nexus-setup/n8n-workflows/`
**Database**: PostgreSQL on nexus (10.0.0.11:5432)
**Schemas**: `health`, `nutrition`, `finance`, `core`

## Claude Agent Notes

**State files used by Claude Coder**:
- `~/Cyber/Infrastructure/ClaudeCoder/state.md` - TODO list
- `~/Cyber/Dev/Nexus-mobile/state.md` - App state

**Rules**:
- ONE small change per session
- Commits directly to main
- Don't touch: `DesignSystem.swift`, working views

## Archived Docs

Old documentation moved to `Documentation/_archive/`.
Reference if needed for historical context.
