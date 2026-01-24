# LifeOS

Personal life data hub - unified monorepo combining iOS app, backend infrastructure, and orchestration.

## Structure

```
LifeOS/
├── ios/              # iOS app (Swift/SwiftUI)
│   └── Nexus/        # Xcode project
├── backend/          # Infrastructure
│   ├── migrations/   # PostgreSQL migrations
│   ├── scripts/      # Import scripts, utilities
│   └── n8n-workflows/# n8n automation workflows
└── ops/              # Orchestration
    ├── state.md      # System state and evidence
    ├── queue.md      # Task queue
    ├── decisions.md  # Architectural Decision Log
    └── artifacts/    # SQL, configs, reports
```

## Components

### iOS App (`ios/`)
- Swift/SwiftUI
- MVVM architecture
- Features: Today dashboard, finance tracking, health integration
- HealthKit integration for weight/steps

### Backend (`backend/`)
- PostgreSQL database on `nexus` server
- n8n workflows for data ingestion
- SMS import from macOS Messages
- Receipt parsing (Carrefour, etc.)

### Orchestration (`ops/`)
- Claude Coder automation
- Claude Auditor verification
- Task queue and state tracking
- Milestone-based development

## Quick Start

```bash
# iOS Development
cd ios && open Nexus.xcodeproj

# Backend Scripts
cd backend/scripts
npm install
node import-sms-transactions.js

# View System State
cat ops/state.md
```

## History

This repo combines:
- [Nexus-setup](https://github.com/Arafaa199/Nexus-setup) → `backend/`
- [Nexus-mobile](https://github.com/Arafaa199/Nexus-mobile) → `ios/`
- LifeOS-Ops (local) → `ops/`

Git history preserved from all sources.
