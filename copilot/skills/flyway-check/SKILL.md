---
name: flyway-check
description: >
  Use when asked about DB migrations, Flyway status, schema version, pending migrations, or schema drift.
---
# Flyway Status Check

Run: bash ~/.copilot/skills/flyway-check/flyway-check.sh [database]

The database argument defaults to `$DB_NAME`, then `dev`. Host and port come from
`DB_HOST`/`DB_PORT` (default localhost:5432); `DB_URL` overrides all of them when no argument is given.
`DB_USER` defaults to `dev`. No password is sent (local DBs use trust auth); `DB_PASS` and `.env` are ignored.

Run from the repo root. When the flyway config lives in a module, set `FLYWAY_MODULE`:
  FLYWAY_MODULE=mono-quarkus bash ~/.copilot/skills/flyway-check/flyway-check.sh

Report: current schema version, count + names of pending migrations, any failures/checksum mismatches.
Never run flyway:migrate, flyway:clean, or flyway:repair from this skill.
