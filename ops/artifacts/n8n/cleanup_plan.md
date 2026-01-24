# n8n Workflow Cleanup Plan

**Generated:** 2026-01-25
**Total Workflows:** 47
**Active in JSON:** 2

## Summary

| Status | Count | Action |
|--------|-------|--------|
| Keep Active | 2 | Verify working |
| Keep (Core Webhooks) | 15 | May need activation |
| Consolidate | 6 | Merge duplicates |
| Archive/Delete | 14 | Unused or deprecated |
| Review | 10 | Check if still needed |

---

## KEEP ACTIVE (2)

These are currently active and should remain so:

| Workflow | Trigger | Notes |
|----------|---------|-------|
| `Nexus: Daily Life Summary API` | webhook | Core dashboard API |
| `LifeOS: Weekly Insight Report` | schedule (Sun 8am) | Weekly email |

---

## KEEP - Core Webhooks (15)

Essential webhooks for iOS app and system operation:

| Workflow | Purpose | Status |
|----------|---------|--------|
| `Nexus - Add Income Webhook (Validated)` | Income with validation | **USE THIS** |
| `Nexus - Expense Log Webhook` | Quick expense logging | Keep |
| `Nexus: Finance Dashboard API` | Dashboard data | Keep |
| `Nexus: Finance Summary API` | Finance summary | Keep |
| `Nexus - Delete Transaction Webhook` | Transaction CRUD | Keep |
| `Nexus - Update Transaction Webhook` | Transaction CRUD | Keep |
| `Nexus - Fetch Budgets Webhook` | Budget API | Keep |
| `Nexus - Set Budget Webhook` | Budget API | Keep |
| `Nexus - Delete Budget Webhook` | Budget API | Keep |
| `Nexus: Sleep Fetch Webhook` | WHOOP data | Keep |
| `Nexus: Sleep History Webhook` | Sleep history | Keep |
| `Nexus Location Webhook` | Location tracking | Keep |
| `Nexus Behavioral Event Webhook` | Behavioral signals | Keep |
| `GitHub Activity Sync` | GitHub integration | Keep (enable) |
| `Nexus: Health Metrics Sync` | WHOOP sync | Keep (enable) |

---

## CONSOLIDATE - Duplicates (6)

### Income Webhooks (3 → 1)
- `Nexus - Add Income Webhook` - **DELETE** (old version)
- `Nexus - Add Income Webhook (Simple)` - **DELETE** (superseded)
- `Nexus - Add Income Webhook (Validated)` - **KEEP** (current version)

### Receipt Ingest (3 → 1)
- `Nexus - Receipt Raw Ingest` - **DELETE** (v1)
- `Nexus - Receipt Raw Ingest v2` - **DELETE** (v2)
- `Receipt Ingest Minimal` - **KEEP** (current version)

---

## ARCHIVE/DELETE - Unused (14)

| Workflow | Reason |
|----------|--------|
| `API Authentication Example` | Example/template only |
| `Nexus - Auto SMS Import` | Replaced by launchd fswatch |
| `Nexus - Trigger SMS Import via API` | Has executeCommand error |
| `Nexus: Daily Summary API` | Superseded by Daily Life Summary |
| `Nexus: Daily Summary Update` | Deprecated |
| `Nexus: Dashboard Today API` | Superseded |
| `Nexus - Finance Summary Webhook` | Duplicate of Finance Summary API |
| `Nexus: Food Log Webhook` | Not used by iOS app |
| `Nexus: Mood Log Webhook` | Not used by iOS app |
| `Nexus: Weight Log Webhook` | Weight via HealthKit now |
| `Nexus: Workout Log Webhook` | Not used |
| `Nexus - AI Insights Webhook` | Claude-dependent, unused |
| `Nexus: Nightly Refresh Facts` | Can be manual |
| `Obico - Events Webhook` | 3D printer events, unused |

---

## REVIEW - Check Usage (10)

| Workflow | Question |
|----------|----------|
| `Carrefour Gmail Receipt Automation` | Is OAuth working? |
| `Nexus: Cleanup Stale Events` | Is this needed? |
| `Nexus: Finance Planning API` | Used by iOS? |
| `Nexus: Installment Plan Webhook` | Used by iOS? |
| `Nexus: Fetch Installments Webhook` | Used by iOS? |
| `Nexus - Monthly Trends Webhook` | Used by iOS? |
| `Nexus: Universal Input (Claude Interpreter)` | Experimental? |
| `Nexus Photo Food Logger` | Working? |
| `Nexus: Smart Entry (Local First, Claude Fallback)` | Active use? |
| `Nexus: Telegram Bot` | Still configured? |

---

## Action Plan

### Phase 1: Immediate (Safe)
1. Delete the 3 superseded income webhooks
2. Delete the 2 old receipt ingest versions
3. Delete obvious unused: API example, SMS import, Daily Summary Update

### Phase 2: Verify Then Delete
1. Check iOS app code for webhook usage
2. Review Carrefour Gmail OAuth status
3. Check Telegram bot configuration

### Phase 3: Activation
1. Enable GitHub Activity Sync (cron)
2. Enable Health Metrics Sync (cron)
3. Verify all core webhooks respond

---

## Commands

```bash
# List active workflows in n8n
ssh pivpn "docker exec n8n n8n list:workflow"

# Check workflow executions
ssh pivpn "docker exec n8n n8n list:workflow:executions"

# Disable a workflow
ssh pivpn "docker exec n8n n8n update:workflow --id=<id> --active=false"
```

---

## Notes

- JSON files show 2 active, but n8n UI may differ
- Webhook URLs don't change when workflow is deactivated
- Consider keeping JSON backups before deletion
- Income webhook validated has known issue (E2E test revealed)
