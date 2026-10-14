---
applyTo: "**/*.sql"
---
# SQL / Flyway
- PostgreSQL + Flyway. Migrations named `V1.0_XX__desc.sql` under `database/release1.0/migration/` (test data: `database/release1.0/test/`).
- Next version: take the highest existing `V1.0_XX` across both dirs, +1. Never edit an already-applied migration; add a new one.
- Status: `FLYWAY_MODULE=mono-quarkus bash ~/.copilot/skills/flyway-check/flyway-check.sh [database]` (runs `flyway:info` from the repo root).
- Never run `flyway:clean` or `flyway:repair` without an explicit ask. Don't run `flyway:migrate` unprompted.
- Read-only queries (SELECT/EXPLAIN/SHOW/WITH): `bash ~/.copilot/skills/psql-select/select.sh -h … -U … -d … -c "<sql>"` — same args as psql.
- Plain `psql` only for INSERT/UPDATE/DELETE/DDL. Local DB has no password; never set `PGPASSWORD`; no credentials inline.
- Multi-tenancy (schema-per-tenant): `~/.copilot/memory/patterns/quarkus-postgres-schema-multitenancy.md`.
