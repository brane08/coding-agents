---
name: psql-select
description: Run read-only PostgreSQL queries (SELECT, EXPLAIN, SHOW, WITH) through a wrapper that refuses anything else. Use for any DB inspection; use plain psql only for INSERT/UPDATE/DELETE/DDL.
---
# Read-only psql

Run: bash ~/.copilot/skills/psql-select/select.sh <normal psql args incl. -c "<sql>">

Example: bash ~/.copilot/skills/psql-select/select.sh -h localhost -U dev -d dev -c "SELECT 1"

- Takes the same args as `psql`; the SQL must be passed via exactly one `-c`, one statement (trailing `;` ok). `-f`, `--command` and combined flags like `-Atc` are blocked; pass `-A`/`-t` separately.
- Only runs when the first word of the SQL is SELECT, EXPLAIN, SHOW or WITH; otherwise exits 1 ("blocked").
- The session runs with `default_transaction_read_only=on`, so writes (e.g. `WITH ... DELETE`) fail server-side.
- Short form: `select.sh "<sql>"` or `select.sh <db> "<sql>"` (localhost, user postgres, db prore, `-A -t`).
- Only local hosts are accepted (localhost, 127.0.0.1, ::1, socket paths); `-d` must be a plain database name (no conninfo string or URI). Functions that read server files, reach other servers or end sessions (`pg_ls_dir`, `pg_read_file`, `dblink*`, `set_config`, ...) are blocked.
- Requires `bash` and `psql` on PATH. Local DB needs no password; never set `PGPASSWORD` inline.
