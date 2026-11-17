---
name: flyway-check
description: >
  Use when asked about DB migrations, Flyway status, schema version, pending migrations, or schema drift.
---
# Flyway Status Check

Run: bash ~/.claude/skills/flyway-check/flyway-check.sh [database]

The database argument defaults to `$DB_NAME`, then `dev`. Host and port come from
`DB_HOST`/`DB_PORT` (default localhost:5432); `DB_URL` overrides all of them when no argument is given.
`DB_USER` defaults to `dev`. No password is ever sent (local DBs use trust auth); `DB_PASS` and `.env` are ignored.

Runs from the project root (`$CLAUDE_PROJECT_DIR`, else cwd). If the flyway config lives in a module, set `FLYWAY_MODULE=<module>` (adds `-pl <module> -am`).

Report: current schema version, count + names of pending migrations, any failures/checksum mismatches.
Never delegate flyway:migrate, flyway:clean, or flyway:repair to this skill.
