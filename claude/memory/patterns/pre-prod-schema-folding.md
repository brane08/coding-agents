# Pre-production Flyway schema folding (never for production DBs)

Covers: keeping a pre-production schema as a baseline plus a capped number of interim migrations, folding them back, and the rules around it. Applies only while there is no production data and no history to preserve. Never apply to a production database.

## Rules
- The baseline scripts are the source of truth; interim migrations are a development convenience.
- Two canonical directories only: schema + base seed, and test seed. Never let test seeds reach the classpath location dev mode migrates from.
- Name `V<version>_<order>__<module-or-feature>.sql`: name the module, not the diff. Flyway reads `_` as a version separator (`V1.0_26` = `1.0.26`; use the dotted form in `-Dflyway.baselineVersion`).
- Files are schema-agnostic: no schema name, no `SET search_path`, no `schema.` qualifiers; use `${flyway:defaultSchema}`, `current_schema()` in catalog queries, and `currentSchema=` in the JDBC URL. Never `schema=` in `@Table`.
- Cap interim migrations at 10; fold all into the baseline before adding an 11th.
- Applied migrations are immutable between folds (checksum validation); add a new version instead of editing.

## Fold procedure
1. Move each new column into its owning `CREATE TABLE`, each constraint inline; never leave an `ALTER TABLE` in the baseline for a table the baseline creates.
2. Drop data-only statements (backfills, one-off `UPDATE`s): no-ops on a fresh DB.
3. Verify a no-op: apply the old chain and the new baseline to two scratch DBs, `pg_dump --schema-only` (and data for seeds) diff them before committing.
4. Delete the folded files; list what was folded in the baseline header; do not reintroduce old versions.
5. Grep for old paths after any move (pom properties feeding Flyway `locations` and resource copies fail silently when stale).

## After a fold
- Every dev DB fails checksum validation: drop the schema and re-migrate (preferred). `flyway:repair`/`clean` are allowed on local dev DBs only and are not part of the fold procedure; `flyway:baseline` only per a written runbook (version detection -> backup -> baseline -> migrate).

## Test DB
- Same database, separate test schema (`<app>` dev / `<app>_test`), not a separate DB. Dev data is never touched by the rebuild.
- **Preferred: script-driven rebuild (academy style).** `mvn test` never touches the schema (it runs far more often than migrations change); a script (`database/scripts/recreate-test-db.sh`: refuses dev/public schema, drop + create schema, `flyway:migrate`, load test seed) rebuilds it only after a migration/seed change. Run the script, then the scoped tests. Tests run against whatever schema is current, so a stale schema = rebuild first.
- Maven-bound rebuild (grocery style: root-pom `flyway:clean` + `flyway:migrate` executions on `process-test-resources`) makes every root `mvn test` pay the rebuild and `mvn -f <module>/pom.xml test` skip it; prefer migrating such repos to the script style (manual rebuild today: `mvn -N -q process-test-resources`).
- Check the repo's `.claude/memory/db-rules.md`/`schema-rules.md` for which style it uses.
- Keep test-seed dates `now()`-relative; frozen literals rot time-sensitive tests.
- Schema reaches a DB only via a manual migrate run (no auto-migrate on app start/stop: `migrate-at-start`/`clean-at-start` false in every profile). Where the Flyway plugin is declared once in the root pom with `<inherited>false</inherited>` (grocery-style), run it with `-N`; other layouts (academy: plugin config in the data module, no executions) run `-pl <data module>` or the repo script.
- Add an entity-vs-`information_schema` validation test; no CI gate means run it locally.
- Use `127.0.0.1`, not `localhost` (IPv6 hang in Agroal).
