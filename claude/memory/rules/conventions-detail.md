# Conventions detail (moved out of CLAUDE.md to cut per-turn tokens)

Read when the task touches the area; CLAUDE.md keeps the one-line version.

## Delegation detail
- Read-only search/nav (file discovery, grep, "where is X", log inspection, including
  `cat`/`ls`/`tail`/`head`/`wc`/`sed`/`awk` on files you didn't just create/edit this turn) →
  `code-search`; `Explore` only as fallback. Never in the main thread, via Bash or Grep/Glob.
  Exception: locate-before-edit — one Grep-tool call (no Grep tool in the session → one Bash
  `grep -n` on a single known path) or Read offset/limit on a single known path or a file you
  are about to edit. Read line ranges with Read, never
  `sed -n`/`cat`/`grep -A`; no `|`/`;`/`&&` on lookups (hook-denied). Two or more lookups →
  dispatch. Don't re-grep a `code-search` result; Read the lines it reported.
- Read-only git queries (`log`/`diff`/`show`/`blame`) — batch into one `code-search` dispatch
  when you need more than one; a single `git status` inline is fine.
- Tests: `bash ~/.claude/skills/mvn-test/test.sh <module> [Class]` (Java) or
  `bash ~/.claude/skills/ng-verify/verify.sh <dir> --include=<spec-glob> --summary` (Angular;
  drop `--include` only for a full run); on failure → `test-aggregator` for the rerun list.
  Exception: one single-class `test.sh <module> <Class>` rerun after a fix you just made.
- Third-party jar API: prefer source (`-sources.jar`, `unzip -p`) over `javap`; javap only when
  no source exists.
- Flyway status → `quick-triage` running `bash ~/.claude/skills/flyway-check/flyway-check.sh`
  (`FLYWAY_MODULE=<module>` when the config is in a module); the status script is read-only —
  migrate/clean/repair only via explicit `mvn`/`mvnw flyway:*` on local dev DBs. Next migration
  version / pending / listing → `flyway-next` (it Globs the migration dirs; not `ls`, not in the
  main thread). On a local dev DB `flyway:clean`/`repair` are allowed but normally unneeded
  (prefer drop schema + re-migrate); `flyway:baseline` only per a written runbook; never prod.
- Ad hoc read-only agents (`general-purpose`/`Explore`) get `model: haiku`; `sonnet` only when
  the agent must reason about *why*, not *where*. Some subagents lack Grep/Glob/Monitor — prompt
  them with Bash `grep`/Read alternatives.
- Review waves: spec-compliance → haiku; code-quality and final branch review → sonnet. Opus
  only when the diff touches auth, crypto, concurrency, or data migration — say so.
- Don't edit CLAUDE.md mid-session (cached prefix); no concurrent Maven/test-DB use from
  subagents (`patterns/agent-context-cost.md`).

## Stack detail
- DB: all `mvn`/`mvnw flyway:*` goals incl. migrate/clean/repair are allowed without a prompt,
  local dev DBs only — never prod hosts/names; run only when asked.
- Python multi-package/uv-workspace repo: scope `pytest` to the relevant package dir(s), not
  repo root — unscoped collection breaks on sibling projects' conftests.
- Test DB: tests use a separate schema in the same db (`grocery_test`, `academy_test`), not
  another db; query `<schema>.<table>`. Preferred (academy style): `mvn test` never rebuilds the
  test schema; rebuild only after a migration/seed change via the repo's `recreate-test-db.sh`,
  then run scoped tests. Grocery still rebuilds on root `mvn test` until migrated — see
  `patterns/pre-prod-schema-folding.md` and the repo's db notes.

## psql
- SELECT/EXPLAIN/SHOW → `bash ~/.claude/skills/psql-select/select.sh "<sql>"` (local Postgres:
  localhost, user postgres, db prore, `-A -t`) or `select.sh <db> "<sql>"` for another db.
  Exactly one `-c` and one statement; pass `-A`/`-t` separately (combined `-Atc`, `-f`,
  `--command` are blocked). Local DB has no password — never set `PGPASSWORD`.
- Plain `psql -h localhost` is allowed without a prompt (local dev DB only) and is for
  INSERT/UPDATE/DELETE/DDL; read-only queries (incl. in subagents or scripts) still go through
  `select.sh` (server-side read-only). Non-local hosts always prompt; dropping `prore`/`prore_test` is denied.

## Don't (full)
- No `cd x &&` prefixes (hook-denied) — cwd persists. Plain `git …` in the current repo (works
  from any subdirectory); `git -C <abs repo>` only for a different repo (prompts). Maven:
  `mvn … -pl <module> -am` from the repo root (`-f <abs>/pom.xml` only outside cwd); `npm
  --prefix`, `ng`, `pytest <pkg dir>`: pass a path, don't `cd`.
- One command per Bash call (parallel calls when independent) — no `;`/`&&`/`|` chains or
  `cmd; rm …` tails; compound commands defeat allow rules and prompt. In subagents use
  `Grep`/`Glob` when the session has them, else one in-project Bash `grep`/`find` (no pipes, no
  chains). Put "one command per call, no chaining, Read not `sed -n`" in every ad hoc agent prompt.
- No `sed -i` / `cat > f` / `printf … >> f` / heredoc writes — use `Edit`/`Write` (append =
  Edit anchored on the file's last line). No inline `python3` heredocs: write the script to the
  scratchpad and run `python3 -I <script>`, or use `jq`.
- `.claude/memory/**` tracking edits: one row or block per `Edit`; multi-row edits trip the
  auto-mode classifier. If one is denied, don't retry: mark the item BLOCKED (reason) and
  continue; list it in the final status.
- Skill/hook scripts: `bash|zsh|ksh ~/.claude/skills/<skill>/<script>.sh …` (any of the three
  is allowed; scripts re-exec into their own shell). Always `~/.claude/…` — never `$HOME`,
  `/Users/…` or `/home/…`: allow rules only match `~`, a full path prompts or is blocked.
- `test.sh` takes only `[<module> [Class]]` (flags are rejected); `--summary` is `verify.sh` only.
- Skill logs (`mvn-test`, `mvn-build`, `quarkus-dev`, `ng-verify`) are in
  `<project>/.claude/logs/<skill>.log` (self-ignoring dir), never `/tmp`: Read or Grep them
  there; a `/tmp` path is outside the project and prompts.
- Exclude `node_modules` from `find`/`grep` (`--exclude-dir`, `-not -path`) — deny rules block it.
- `rm`/`mv`/`cp` are denied (admin profile; sandbox: mv/cp ask, `git push`/`git checkout`
  allowed): use `git rm`/`git mv` for tracked files, else
  `bash ~/.claude/skills/guarded-fs/guarded-fs.sh rm|mv|cp …` (cwd-confined).
- `sudo`/`curl`/`wget`/`ssh`/destructive git ops are denied or ask — ask the user to run them.
- Don't add comments restating what code obviously does; don't add unrequested README/docs files.
- Don't resolve an npm peer-dependency conflict with `--legacy-peer-deps` on a
  security-relevant package (auth, crypto, http-client) — pin a compatible version instead.
