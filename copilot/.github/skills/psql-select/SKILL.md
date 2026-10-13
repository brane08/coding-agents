---
name: psql-select
description: Run read-only PostgreSQL queries (SELECT, EXPLAIN, SHOW, WITH) through a wrapper that refuses anything else. Use for any DB inspection; use plain psql only for INSERT/UPDATE/DELETE/DDL.
---
# Read-only psql

Run: bash .github/skills/psql-select/select.sh <normal psql args incl. -c "<sql>">

Example: bash .github/skills/psql-select/select.sh -h localhost -U dev -d dev -c "SELECT 1"

- Takes the same args as `psql`; the SQL must be passed via `-c`. No `-c` → exit 1.
- Only runs when the first word of the SQL is SELECT, EXPLAIN, SHOW or WITH; otherwise exits 1 ("blocked").
- Only the first word is checked: a `WITH ... DELETE` or multi-statement string would still pass. Write read-only SQL yourself; don't rely on the wrapper as a security boundary.
- Requires `zsh` and `psql` on PATH. Local DB needs no password; never set `PGPASSWORD` inline.
