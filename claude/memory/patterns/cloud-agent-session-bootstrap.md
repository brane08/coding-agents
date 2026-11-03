# Cloud agent session bootstrap (ephemeral container, Java/Maven/Postgres/Angular)

Covers: setup checklist and gotchas for a fresh remote agent session with no Docker and offline or limited network. Repo-specific commands/ports belong in the repo memory.

## Toolchain
- Container may ship an older JDK: install/point `JAVA_HOME` at the required JDK and prepend its `bin` to `PATH` on every `mvn` call (shell state does not persist between Bash calls). Download tarballs into the scratchpad.
- Maven 3 and Node are usually preinstalled; Chromium/Playwright browsers too: use the existing binary as `CHROME_BIN` for Karma, do not reinstall.
- Offline build: `mvn -q -o install -DskipTests`; full rebuild after any shared-module change (stale jars give `NoSuchMethodError`).

## Database
- Do not change the system Postgres to trust auth. Start a throwaway cluster: `initdb` under a temp data dir, run `pg_ctl` as the `postgres` OS user on a non-default port bound to `127.0.0.1`, trust auth on localhost only, create the app DB. Or start the packaged cluster (`pg_ctlcluster <ver> main start`) when present.
- Point test datasources at it with `-D%test.quarkus.datasource.jdbc.url=...` (repeat for named datasources).
- Rebuild the test schema after any migration/seed change; only one agent at a time. Command is per repo: Maven-driven repos rebuild on root `mvn test` (or `mvn -N -q process-test-resources`); script-driven repos need their `recreate-test-db.sh`-style script — `mvn test` will not do it.

## Running tests
- Cloud sessions need -D datasource flags test.sh rejects: inline `mvn -pl <module> -am -Dtest=<Class>` is the allowed exception.
- Spot test with `-Dtest=X -Dsurefire.failIfNoSpecifiedTests=false`, `-Djacoco.skip=true`; add `-am` when a sibling module changed.
- Full suite once, before pushing; run in the background, wait with an until-loop Monitor (foreground `sleep` is blocked); check surefire report files.
- A strict production frontend build inside Maven (Quinoa) catches template errors that `tsc` on specs misses.
- Architecture tests that read sibling modules fail under a whole-reactor `mvn test` (classes load from `target/classes`): `mvn install -DskipTests` those modules, then run the test with `-pl`.
- Mock-based unit tests need stubs for any new collaborator or query a service starts using (common full-suite-only failure).
- Angular: `ng test --watch=false --browsers=CI` with a karma config defining a headless `--no-sandbox` launcher named `CI`.

## Concurrency and agents
- Never run two Maven builds at once: shared `target/` and test DB give bogus boot/FK failures and phantom mass 500s. Subagents (incl. quick-triage) run one test script at a time, never concurrently; full suite only when preparing the PR.
- At most 2 subagents in cloud sessions (disjoint scopes); 4 elsewhere.
- Stop hooks nag about uncommitted/unpushed work while subagents are mid-flight; ignore until they hand back.

## Shell and git
- `pkill -f <pattern>` can match the calling shell: use `pgrep -f '[p]attern'` and kill by pid.
- Scratch files go in the session scratchpad, not the repo.
- Squash to one commit before the PR (a 'pr' request is the go-ahead), then `--force-with-lease` on your own branch.
- After a squash-merge of the PR the old branch cannot be pushed: branch fresh from `origin/<default>` and apply the diff (force-push/`reset --hard` may be blocked by the classifier).
