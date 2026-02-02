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
| Food Logging | `FoodLogView.swift` | `POST /webhook/nexus-food-log` |
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

**n8n Workflows**: `backend/n8n-workflows/` (symlinked from `~/Cyber/Infrastructure/Nexus-setup/`)
**Database**: PostgreSQL on nexus (10.0.0.11:5432)
**Pipeline**: Source → raw → normalized → life.daily_facts
**Schemas**: `raw`, `normalized`, `life`, `finance`, `health`, `nutrition`, `ops`, `insights`
**Timezone**: All dates use Dubai time (Asia/Dubai, UTC+4). See `Constants.Dubai` in iOS, `life.dubai_today()` in SQL.

See `LifeOS_Technical_Documentation.md` at the repo root for full schema and API docs.

## Claude Agent Notes

**Agents** (`~/Cyber/Infrastructure/ClaudeAgents/`):
- **Coder** (every 9 min): Executes ONE `ops/queue.md` task, commits to main
- **Auditor** (every 35 min): Reviews commits, PASS/BLOCK
- **SysAdmin** (daily 22:15): Read-only health check

**State**: `ops/state.md`, `ops/queue.md`, `ops/decisions.md`, `ops/alerts.md`

## Archived Docs

Old documentation moved to `Documentation/_archive/`.
Reference if needed for historical context.
