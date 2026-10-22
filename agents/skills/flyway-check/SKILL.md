---
name: flyway-check
description: Report Flyway migration status for a local Postgres - current schema version, pending migrations, failures and checksum mismatches. Use when asked about DB migrations, Flyway status, schema version, pending migrations, or schema drift. Read-only; never runs migrate, clean or repair.
compatibility: Requires bash and Maven with the Flyway plugin configured in the project; local Postgres.
metadata:
  version: "1.0"
---
# Flyway Status Check

Run: `bash ~/.agents/skills/flyway-check/flyway-check.sh [database]`

The database argument defaults to `$DB_NAME`, then `dev`. Host and port come from
`DB_HOST`/`DB_PORT` (default localhost:5432); `DB_URL` overrides all of them when no argument is given.
`DB_USER` defaults to `dev`. No password is ever sent (local DBs use trust auth); `DB_PASS` and `.env` are ignored.

Runs from the project root (`$AGENT_PROJECT_DIR`, else the current directory).
If the Flyway config lives in a module, set `FLYWAY_MODULE=<module>` (adds `-pl <module> -am`).

Report: current schema version, count and names of pending migrations, any failures or checksum mismatches.
This skill only reports status. Running `flyway:migrate`, `flyway:clean` or `flyway:repair` is a separate, explicit request.
