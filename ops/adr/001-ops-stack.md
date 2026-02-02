# ADR-001: Ops Scalability Stack

**Status**: Accepted
**Date**: 2026-02-02
**Author**: human + coder

## Context

LifeOS grew to 7 domains (finance, health, dashboard, calendar, documents, notes, behavioral) with 30+ n8n endpoints, 130+ DB migrations, and an iOS app. The system relied entirely on CLAUDE.md (600+ lines) as the source of truth for auditing and maintenance. As the system scales, this approach doesn't hold:

- No automated way to detect if an endpoint's response shape changed
- No schema drift detection between what's deployed and what's expected
- No machine-readable registry of features, frozen files, or domain ownership
- The auditor had no way to generate tasks from infrastructure health signals

## Decision

Build a 3-tier ops stack:

**Tier 1 — Immediate monitoring:**
- JSON contract schemas for all GET endpoints (`ops/contracts/*.json`)
- `ops/check.sh` — read-only smoke tests (SSH to pivpn, curl endpoints, validate contracts)
- `ops/schema_snapshot.sh` — nightly pg_dump schema diff
- `GET /webhook/ops-health` — n8n endpoint returning DB/pipeline staleness
- `ops/nightly.sh` + launchd — automated nightly reporting

**Tier 2 — Testing and registry:**
- SMS replay harness wrapping existing `test-sms-classifier.js`
- `ops/feature_manifest.yaml` — machine-readable domain registry
- Auditor reads manifest for frozen file enforcement and task generation

**Tier 3 — Governance:**
- ADR templates and initial records
- ADR enforcement in auditor (WARNING, not BLOCK)

Key constraints:
- No npm dependencies in ops scripts (bash + jq + ssh only)
- No mutations in smoke tests (GET only)
- All output under `LifeOS/ops/` (monorepo)

## Alternatives Considered

1. **Full test framework (Jest/Vitest)**: Rejected — adds npm dependency, overkill for infrastructure health checks
2. **Docker-based test env**: Deferred to ADR-002 — requires nexus_test DB, seed data, significant setup
3. **GitHub Actions CI**: Not applicable — n8n and DB are on-prem, can't reach from GitHub runners

## Consequences

- **Positive**: Auditor can now detect contract drift, frozen file violations, and infrastructure issues automatically. Nightly reports provide a paper trail. Feature manifest serves as living documentation.
- **Negative**: check.sh adds ~2 min of SSH calls per run. Schema snapshots are ~26K lines each (7 kept = ~180K on disk).
- **Risks**: SSH timeouts could cause false failures in check.sh. Contracts need manual updates when endpoint shapes change intentionally.
