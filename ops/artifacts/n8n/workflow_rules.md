# n8n Workflow Rules

## Canonical Workflow Rules

### 1. One Workflow Per Endpoint

**Rule:** Each webhook endpoint MUST have exactly ONE active workflow.

**Rationale:** Multiple active workflows on the same path cause undefined behavior. n8n may route requests to any of them unpredictably.

**Enforcement:** Run `scripts/n8n_audit.sh` before deployments.

---

### 2. Naming Convention

**Format:** `Nexus: <Action> <Entity> <Type>`

**Examples:**
- `Nexus: Add Transaction API` ✓
- `Nexus: Sleep Fetch Webhook` ✓
- `Nexus: Nightly Refresh Facts` ✓

**Avoid:**
- `Nexus - Income Webhook v3 (Robust)` ✗ (version in name)
- `Nexus - Add Income Webhook (Validated)` ✗ (qualifier in name)
- `test-income-webhook` ✗ (test in name, wrong format)

**Types:**
- `API` - Request/response webhook
- `Webhook` - Fire-and-forget webhook
- (no suffix) - Scheduled/cron workflow

---

### 3. Deactivation Policy

**Before deactivating:**
1. Verify replacement workflow is active and tested
2. Run E2E tests if applicable
3. Keep workflow in n8n for 30 days (inactive)

**After 30 days inactive:**
1. Export workflow JSON to `artifacts/n8n/archived/`
2. Delete from n8n

**Never delete without export.**

---

### 4. Adding New Workflows

1. Check `active_workflows.md` for existing endpoint
2. If exists: Update existing workflow, don't create new
3. If new endpoint needed:
   - Create workflow with proper naming
   - Test locally with curl
   - Run `scripts/n8n_audit.sh` to verify no conflicts
   - Update `active_workflows.md`

---

### 5. Removing Workflows

1. Deactivate workflow in n8n (don't delete)
2. Wait 7 days minimum (watch for errors)
3. Run `scripts/n8n_audit.sh` to confirm inactive
4. Export to `artifacts/n8n/archived/<workflow-id>.json`
5. Delete from n8n
6. Update `active_workflows.md`

---

### 6. Version Management

**Do NOT** put version numbers in workflow names.

**Instead:**
1. Update existing workflow in place
2. Test with E2E harness
3. n8n maintains version history internally

**If major rewrite needed:**
1. Create new workflow with `(Canonical)` suffix
2. Test thoroughly
3. Deactivate old workflow
4. Rename new workflow (remove suffix)

---

## Audit Checklist

Run `scripts/n8n_audit.sh` weekly or before deployments:

- [ ] No duplicate endpoints (multiple active on same path)
- [ ] No workflows with "(old|test|backup|debug)" in name that are active
- [ ] All Nexus endpoints have exactly one owner
- [ ] `active_workflows.md` matches actual state

---

## Emergency Procedures

### Wrong Workflow Responding

1. Identify correct workflow ID from `active_workflows.md`
2. Deactivate ALL workflows on that endpoint
3. Activate ONLY the canonical one
4. Restart n8n: `ssh pivpn "docker restart n8n"`
5. Test endpoint manually

### Workflow Lost/Deleted

1. Check `artifacts/n8n/archived/` for export
2. If found: Import with `n8n import:workflow --input=<file>`
3. If not found: Check n8n internal backups or recreate from code

---

## File Locations

| File | Purpose |
|------|---------|
| `artifacts/n8n/active_workflows.md` | Authoritative list of active workflows |
| `artifacts/n8n/workflow_rules.md` | This document |
| `artifacts/n8n/archived/` | Exported inactive workflows |
| `scripts/n8n_audit.sh` | Audit script for violations |
| `n8n-workflows/*.json` | Canonical workflow definitions |
