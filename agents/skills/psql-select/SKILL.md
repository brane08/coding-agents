---
name: psql-select
description: Run read-only SQL (SELECT, EXPLAIN, SHOW, WITH) against the local Postgres through a wrapper that blocks writes. Use for ANY read-only database query, such as row counts, data checks, schema lookups and verifying test data, in every project. Use it instead of plain psql for reads.
compatibility: Requires zsh (the script re-execs itself into zsh) and psql; a local Postgres on localhost with trust authentication.
metadata:
  version: "1.0"
---
# Read-only psql

Run: `bash ~/.agents/skills/psql-select/select.sh "<sql>"`
Other database: `bash ~/.agents/skills/psql-select/select.sh <db> "<sql>"`

The local Postgres is trusted, so any database on it works from any project (prore, prore_test, pagila, sakila, ...).
Defaults: host localhost, user postgres, db prore, unaligned tuples-only output (`-A -t`). No password; never set `PGPASSWORD`.

- Use the short form above. The long `-h/-U/-d/-A/-t/-c` form works for a non-default host, but it is not covered by allowlists and prompts.
- One statement per call; `;` inside the SQL is blocked. Operators like `||` are fine.
- SQL must start with SELECT, EXPLAIN, SHOW or WITH; the session is also read-only server-side.
- INSERT/UPDATE/DELETE/DDL need plain `psql` (prompts, by design). Never use plain `psql` for a read.
- Never point it at a remote or prod host.
