# API Contracts

> **Moved to:** [`backend/contracts/`](backend/contracts/README.md)

The single source of truth for all API endpoint contracts is now in `backend/contracts/`.

## Quick Links

- [README & Index](backend/contracts/README.md)
- [Dashboard](backend/contracts/dashboard.md) - Dashboard, sleep, sync
- [Finance](backend/contracts/finance.md) - Transactions, budgets, recurring
- [Health](backend/contracts/health.md) - Weight, mood, workouts, supplements
- [Nutrition](backend/contracts/nutrition.md) - Food logging, water, fasting
- [Documents](backend/contracts/documents.md) - Document tracking, reminders
- [Notes](backend/contracts/notes.md) - Obsidian notes index
- [Music](backend/contracts/music.md) - Apple Music listening
- [Home](backend/contracts/home.md) - Home Assistant integration
- [Receipts](backend/contracts/receipts.md) - Receipt parsing
- [Architecture](backend/contracts/architecture.md) - Data flow, ledger design

## Validation

```bash
# Test all endpoints
python backend/scripts/test_contracts.py

# Validate single response
./ops/lib/validate-contract.sh backend/contracts/_schemas/nexus-dashboard-today.json response.json
```

---

*This file is a redirect. Do not edit - update backend/contracts/ instead.*
