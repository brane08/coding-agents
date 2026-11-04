# Global preferences

Detail lives in `~/.claude/memory/` — start at `memory/INDEX.md`; `memory/rules/` holds the
long-form rules referenced below.

## Output
- Terse: no preamble, no restating the request, no summary unless asked.
- Code blocks: complete, copy-paste-ready, no "..." truncation unless huge.
- Skip well-known-concept explanations unless asked.
- Pattern/template/doc requests ("give a pattern", "summary I can reuse"): reply with the raw
  markdown in one code block (use a 4-backtick fence if it contains fences), nothing rendered.

## Delegation (token discipline)
- Read-only search/nav (file discovery, grep, "where is X", log inspection,
  including `cat`/`ls`/`tail`/`head`/`wc`/`sed`/`awk` on files you didn't just
  create/edit this turn) → `code-search`; `Explore` only as fallback. Never do
  this in the main thread, via Bash or the Grep/Glob tools. Exception: locate-before-edit —
  one Grep-tool call (not Bash `grep`) or Read offset/limit on a single known path or a file
  you are about to edit. Read line ranges with Read, never `sed -n`/`cat`/`grep -A`; no
  `|`/`;`/`&&` on lookups (hook-denied). Two or more lookups → dispatch. Don't re-grep a
  `code-search` result; Read the lines it reported.
- Read-only git queries (`log`/`diff`/`show`/`blame`) — batch into one `code-search`
  dispatch when you need more than one; a single `git status` inline is fine.
- Tests never run inline. Dispatch to `quick-triage`:
  `bash ~/.claude/skills/mvn-test/test.sh <module> [Class]` (Java) or
  `bash ~/.claude/skills/ng-verify/verify.sh <dir> --include=<spec-glob> --summary` (Angular;
  drop `--include` only for a full run); on failure →
  `test-aggregator` for the rerun list. Exception: one single-class `test.sh <module> <Class>`
  rerun after a fix you just made. Other build/log triage → `quick-triage` first.
- Pattern-mirroring boilerplate (DTOs, mappers, CRUD repos, Angular stubs) →
  `boilerplate-gen`. Never for anything involving a design decision.
- Maven dep-tree → `dep-inspect`. Third-party jar API/bytecode → `jar-inspect`; prefer source
  (`-sources.jar`, `unzip -p`) over `javap`; javap only when no source exists.
- Flyway status → `quick-triage` running `bash ~/.claude/skills/flyway-check/flyway-check.sh`
  (`FLYWAY_MODULE=<module>` when the config is in a module); the status script is read-only —
  migrate/clean/repair only via explicit `mvn`/`mvnw flyway:*` on local dev DBs.
  Next migration version / pending / listing migrations → `flyway-next` (it Globs the migration
  dirs; not `ls`, not in the main thread). On a local dev DB `flyway:clean`/`repair` are allowed
  but normally unneeded (prefer drop schema + re-migrate); `flyway:baseline` only per a written
  runbook; never against prod.
- Entity wiring (DTO→Entity→Mapper→Producers→Resource) → `stack-check`. Workflow wiring
  (deriveType/ACTION_MAP/wait+getAndRemoveResponse/tests) → `workflow-check`.
- Main thread is for: edits, architecture decisions, multi-file changes, anything needing
  write/bash side effects. Don't re-read unchanged files already shown this session.
- Resume a dispatched subagent with `SendMessage` (agent id/name), never `Agent` again — that
  spawns a fresh one.
- Never pass `model:` to `code-search`, `quick-triage`, `test-aggregator`, `jar-inspect`,
  `dep-inspect`, `flyway-next`, `stack-check`, `workflow-check`, `boilerplate-gen` — they pin
  haiku already.
- Ad hoc read-only agents (`general-purpose`/`Explore` for "scan X", "list Y") get
  `model: haiku`; `sonnet` only when the agent must reason about *why*, not *where*. Some
  subagents lack Grep/Glob/Monitor — prompt them with Bash `grep`/Read alternatives.
- Review waves: spec-compliance → haiku; code-quality and final branch review → sonnet. Opus
  only when the diff touches auth, crypto, concurrency, or data migration — say so. The main
  session runs `opusplan` (Opus in plan mode); this limit applies to subagents and review waves.
- No secrets inline in Bash (`TOKEN="..."`, `Bearer ...`, raw JWTs) — they persist in the
  transcript. Read from an env var or file.
- Hooks/denies (what is blocked, prompted or unreadable, and why): `memory/rules/hooks-and-guards.md`.
- Don't edit CLAUDE.md mid-session (cached prefix); no concurrent Maven/test-DB use from
  subagents (`patterns/agent-context-cost.md`).

## Session length
- On a compaction summary at the start of context, or a shift to unrelated work: at the next
  natural pause say "Session compacted N× — consider /clear or a fresh session." Once per
  task from the 2nd compaction on; never mid-task.

## Stack defaults (assume, don't ask)
- Java: Maven multi-module (`mono-quarkus`), Quarkus + Spring Boot mix, OpenShift target.
- DB: PostgreSQL + Flyway (all `mvn`/`mvnw flyway:*` goals incl. migrate/clean/repair are
  allowed without a prompt, local dev DBs only — never prod hosts/names; run only when asked).
- Frontend: Angular.
- Shell: zsh, macOS or Ubuntu/Debian VM — no bash-only syntax unless asked.
- Python multi-package/uv-workspace repo: scope `pytest` to the relevant package dir(s),
  not repo root — unscoped collection breaks on sibling projects' conftests.
- Test DB: tests use a separate schema in the same db (`grocery_test`, `academy_test`), not
  another db; query `<schema>.<table>`. Preferred (academy style): `mvn test` never rebuilds the
  test schema; rebuild only after a migration/seed change via the repo's `recreate-test-db.sh`,
  then run scoped tests. Grocery still rebuilds on root `mvn test` until migrated — see
  `patterns/pre-prod-schema-folding.md` and the repo's db notes.

## Superpowers plugin — constrained use
- Large scope only (new feature/component, multi-file refactor, design with real tradeoffs):
  `writing-plans` → `executing-plans`, then verify by running the tests (via `quick-triage`).
  State the approach directly; no brainstorming step.
- Other superpowers skills: only if explicitly asked by name.

## Tooling gotchas
- `EnterWorktree` branches from `origin/<default-branch>`, not your current branch — pass the
  base explicitly or `git worktree add <path> -b <branch> <base>`; verify with
  `git branch --show-current`/`git log` right after.

## Memory
Before analyzing a library/JAR/framework/internal detail: check `~/.claude/memory/libs/`,
then repo `.claude/memory/`, then decompile/fetch docs only if neither answers it.
`memory/INDEX.md` lists every lib/pattern/rule note; open only what matches.

File new learnings by reuse, not by where learned:
- Library, framework, version quirk, JPMS rule → `~/.claude/memory/libs/<lib-version>.md`
- Reusable design pattern → `~/.claude/memory/patterns/<name>.md`
- Repo-only facts (names/paths/wiring) → repo `.claude/memory/<topic>.md`, linking to the
  global note instead of restating it.
- Working-session record → `~/.claude/memory/sessions/<yyyy-mm-dd>-<topic>.md`, linking to
  libs/patterns notes; list it in `MANIFEST`. Add new notes to `memory/INDEX.md` too.

Keep entries concise and copy-pasteable; no local paths or credentials; never dump raw
decompiled output.

Rules (read before the task): config sync → `rules/config-sync.md` · audits/permission scans →
`rules/session-scans.md` · commit/push/PR → `rules/git-prs.md`.

## psql
- SELECT/EXPLAIN/SHOW → `bash ~/.claude/skills/psql-select/select.sh "<sql>"` (local Postgres:
  localhost, user postgres, db prore, `-A -t`) or `select.sh <db> "<sql>"` for another db.
  Exactly one `-c` and one statement; pass `-A`/`-t` separately (combined `-Atc`, `-f`,
  `--command` are blocked). Local DB has no password — never set `PGPASSWORD`.
- Plain `psql -h localhost` is allowed without a prompt (local dev DB only) and is for
  INSERT/UPDATE/DELETE/DDL; read-only queries (incl. in subagents or scripts) still go through
  `select.sh` (server-side read-only). Non-local hosts always prompt; dropping `prore`/`prore_test` is denied.

## Git / PRs (essentials; full rules in `rules/git-prs.md`)
- Before new work: `bash ~/.claude/skills/pr-squash-sync/sync-check.sh <default>`; current
  branch already squash-merged → new branch from `origin/<default>`.
- Before committing/pushing to an existing branch, check its PR isn't merged
  (`gh pr list --head <branch> --state all --json state`); merged → `pr-squash-sync` skill.
- Commit attribution is exactly one trailer: `Co-Authored-By: Claude <noreply@anthropic.com>`
  (set via `attribution.commit`; don't hand-write it). Nothing else: no `by Claude (...)`, no
  `Claude-Session:`, no URLs/session links, no "Generated with Claude Code". PR descriptions: none.
- Squash to a single commit before opening a PR (1–2 commits max); a "pr"/"squash pr" request
  is the go-ahead, no follow-up question. Never force-push `main`/`master`.

## Auth/role tests
- REST Assured first (`patterns/rest-assured-csv-role-matrix.md`); confirm roles per test user
  via `select.sh` and the endpoint's `@RolesAllowed`/`@PermitAll`; never assume seed ids.

## Don't
- No `cd x &&` prefixes (hook-denied) — cwd persists. Plain `git …` in the current repo (works
  from any subdirectory); `git -C <abs repo>` only for a different repo (prompts). Maven:
  `mvn … -pl <module> -am` from the repo root (`-f <abs>/pom.xml` only outside cwd); `npm
  --prefix`, `ng`, `pytest <pkg dir>`: pass a path, don't `cd`.
- One command per Bash call (parallel calls when independent) — no `;`/`&&`/`|` chains or
  `cmd; rm …` tails; compound commands defeat allow rules and prompt. In subagents use
  `Grep`/`Glob` when the session has them, else one in-project Bash `grep`/`find` (no pipes, no
  chains). Put "one command per call, no chaining, Read not `sed -n`" in every ad hoc agent prompt.
- No `sed -i` / `cat > f` / `printf … >> f` / heredoc writes — use `Edit`/`Write` (append =
  Edit anchored on the file's last line). No inline `python3` heredocs:
  write the script to the scratchpad and run `python3 -I <script>`, or use `jq`.
- `.claude/memory/**` tracking edits: one row or block per `Edit`; multi-row edits trip the
  auto-mode classifier. If one is denied, don't retry: mark the item BLOCKED (reason) and
  continue; list it in the final status.
- Skill/hook scripts: `bash|zsh|ksh ~/.claude/skills/<skill>/<script>.sh …` (any of the three
  is allowed; scripts re-exec into their own shell). Always `~/.claude/…` — never `$HOME`,
  `/Users/…` or `/home/…`: allow rules only match `~`, a full path prompts or is blocked.
- `test.sh` takes only `[<module> [Class]]` (flags are rejected); `--summary` is `verify.sh` only.
- Skill logs (`mvn-test`, `mvn-build`, `quarkus-dev`, `ng-verify`) are in `<project>/.claude/logs/<skill>.log`
  (self-ignoring dir), never `/tmp`: Read or Grep them there; a `/tmp` path is outside the project and prompts.
- Exclude `node_modules` from `find`/`grep` (`--exclude-dir`, `-not -path`) — deny rules block it.
- `rm`/`mv`/`cp` are denied (admin profile; sandbox: mv/cp ask, `git push`/`git checkout`
  allowed): use `git rm`/`git mv` for tracked files, else
  `bash ~/.claude/skills/guarded-fs/guarded-fs.sh rm|mv|cp …` (cwd-confined).
- `sudo`/`curl`/`wget`/`ssh`/destructive git ops are denied or ask — ask the user to run them.
- Don't add comments restating what code obviously does.
- Don't add unrequested README/docs files.
- Don't resolve an npm peer-dependency conflict with `--legacy-peer-deps` on a
  security-relevant package (auth, crypto, http-client) — pin a compatible version instead.
