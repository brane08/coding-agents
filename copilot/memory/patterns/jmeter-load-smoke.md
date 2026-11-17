# JMeter load/perf run — pre-flight smoke checks

Abort the run if any check fails:

1. App reachable: `uvx --from httpie http --headers GET <url>` on a public endpoint (e.g. `/rest/products`) → 200 on the host/port under test. HTTP calls use httpie via `uvx`, never `curl`/`wget`; run it as its own command, not chained.
2. Schema migrated: `flyway:info` (via `quick-triage`) shows no pending migrations.
3. DB seeded: `select.sh` count checks on the tables the plan touches (users, products, orders as relevant).
4. Cookie/user ids in the plan exist in the DB the *running app* uses (dev vs test DB).

Run via `quick-triage`; judge results from the result CSVs, not the agent summary.

Functional role×endpoint×status matrices are not a JMeter job — see `rest-assured-csv-role-matrix.md`.
