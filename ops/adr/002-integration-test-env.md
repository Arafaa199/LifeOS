# ADR-002: Integration Test Environment

**Status**: Proposed
**Date**: 2026-02-02
**Author**: coder

## Context

Current testing is limited to:
- SMS classifier unit tests (23 cases)
- Contract validation against live endpoints (read-only)
- Manual testing via iOS simulator

There's no way to test write operations (POST endpoints, transaction creation, receipt ingestion) without hitting the production database. This limits confidence in changes to ingestion pipelines.

## Decision

Design (not implement yet) an integration test environment:

### Components

1. **Test database**: `nexus_test` on the nexus server
   - Created via `CREATE DATABASE nexus_test TEMPLATE nexus` or migrations
   - Populated with seed data from `ops/test/seed.sql`
   - Reset before each test run

2. **Seed data** (`ops/test/seed.sql`):
   - 10 representative transactions (various categories, currencies)
   - 3 recurring items
   - 5 merchant rules
   - 2 budgets
   - 1 receipt with items
   - Minimal health data (1 day of WHOOP)

3. **n8n test mode**:
   - Separate Postgres credential pointing to `nexus_test`
   - Workflows cloned with test credential (or env var switch)
   - Test webhooks at `/webhook-test/` path

4. **Test runner** (`ops/test/integration.sh`):
   - Reset test DB → run seed → execute POST tests → verify state → cleanup
   - Tests: create transaction, create recurring item, SMS import dry-run, receipt ingest

### Blockers
- n8n doesn't support credential switching via env vars natively
- Need to either clone workflows or use n8n API to swap credentials
- Test DB needs same schema as prod (run all migrations)

## Alternatives Considered

1. **Mock n8n locally**: Too complex — n8n has many node types and behaviors
2. **Test against prod with rollback**: Risky — hard to guarantee clean rollback
3. **SQLite test DB**: Incompatible — we use Postgres-specific features (JSONB, triggers)

## Consequences

- **Positive**: Safe write-path testing, catch ingestion regressions before prod
- **Negative**: Maintenance burden of keeping test DB schema in sync
- **Risks**: Test isolation — must ensure test runs never touch prod DB
