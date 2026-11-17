---
name: psql-select
description: >
  Use for ANY read-only database query (SELECT, EXPLAIN, SHOW, WITH) against the local Postgres: row counts, data checks, schema lookups, verifying test data. Always use this instead of plain psql, in every project and in subagents.
---
# Read-only psql

Run: bash ~/.claude/skills/psql-select/select.sh "<sql>"
Other database: bash ~/.claude/skills/psql-select/select.sh <db> "<sql>"

The local Postgres is trusted, so any database on it works from any project (prore, prore_test, pagila, sakila, ...).
Defaults: host localhost, user postgres, db prore, unaligned tuples-only output (`-A -t`). No password; never set `PGPASSWORD`.

- Use the short form above. Do not use the long `-h/-U/-d/-A/-t/-c` form: it prompts for permission, the short form does not. The long form is only for a non-default host.
- One statement per call; `;` inside the SQL is blocked. Operators like `||` are fine.
- SQL must start with SELECT, EXPLAIN, SHOW or WITH; the session is also read-only server-side.
- INSERT/UPDATE/DELETE/DDL need plain `psql` (prompts, by design). Never use plain `psql` for a read.
- Never point it at a remote or prod host.
