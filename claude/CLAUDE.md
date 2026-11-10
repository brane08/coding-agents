# Global preferences

Detail lives in `~/.claude/memory/` — start at `memory/INDEX.md`; `memory/rules/` holds the
long-form rules. Full delegation/stack/psql/don't detail: `rules/conventions-detail.md`.

## Output
- Terse: no preamble, no restating the request, no summary unless asked.
- Code blocks: complete, copy-paste-ready, no "..." truncation unless huge.
- Skip well-known-concept explanations unless asked.
- Pattern/template/doc requests ("give a pattern", "summary I can reuse"): reply with the raw
  markdown in one code block (use a 4-backtick fence if it contains fences), nothing rendered.

## Delegation (token discipline)
- Read-only search/nav/log inspection (incl. `cat`/`ls`/`tail`/`head`/`wc`/`sed`/`awk` on files
  you didn't just edit) → `code-search`; `Explore` only as fallback. Never in the main thread via
  Bash or Grep/Glob. Exception: locate-before-edit — one Grep-tool call (no Grep tool in the
  session → one Bash `grep -n` on a single known path) or Read offset/limit on a single known
  path. Read line ranges with Read, never `sed -n`/`cat`/`grep -A`; no
  `|`/`;`/`&&` on lookups (hook-denied). Two or more lookups → dispatch. Don't re-grep a
  `code-search` result. Read-only git queries: batch into one `code-search`; one `git status` inline.
- Tests never run inline → `quick-triage` running
  `bash ~/.claude/skills/mvn-test/test.sh <module> [Class]` (Java) or
  `bash ~/.claude/skills/ng-verify/verify.sh <dir> --include=<spec-glob> --summary` (Angular);
  on failure → `test-aggregator`. Exception: one single-class rerun after a fix just made.
  Other build/log triage → `quick-triage` first.
- Boilerplate mirroring an existing pattern → `boilerplate-gen` (never design decisions).
  Maven dep-tree → `dep-inspect`. Jar API → `jar-inspect` (prefer `-sources.jar`).
- Flyway status → `quick-triage` + `flyway-check.sh`; next version/pending/listing →
  `flyway-next`. Local dev DB only; never prod; `flyway:baseline` only per a written runbook.
- Entity wiring (DTO→Entity→Mapper→Producers→Resource) → `stack-check`. Workflow wiring
  (deriveType/ACTION_MAP/wait+getAndRemoveResponse/tests) → `workflow-check`.
- Main thread: edits, architecture decisions, multi-file changes, side effects. Don't re-read
  unchanged files. Resume a subagent with `SendMessage`, never `Agent` again.
- Never pass `model:` to `code-search`, `quick-triage`, `test-aggregator`, `jar-inspect`,
  `dep-inspect`, `flyway-next`, `stack-check`, `workflow-check`, `boilerplate-gen` — pinned haiku.
- Ad hoc read-only agents get `model: haiku`; `sonnet` only when reasoning about *why*.
- Review waves: spec-compliance → haiku; code-quality and final branch review → sonnet. Opus
  only when the diff touches auth, crypto, concurrency, or data migration — say so. The main
  session runs `opusplan` (Opus in plan mode); this limit applies to subagents and review waves.
- No secrets inline in Bash (`TOKEN="..."`, `Bearer ...`, raw JWTs) — they persist in the
  transcript; read from an env var or file. Hooks/denies:
  `memory/rules/hooks-and-guards.md`. Don't edit CLAUDE.md mid-session (cached prefix); no
  concurrent Maven/test-DB use from subagents (`patterns/agent-context-cost.md`).

## Session length
- On a compaction summary at the start of context, or a shift to unrelated work: at the next
  natural pause say "Session compacted N× — consider /clear or a fresh session." Once per
  task from the 2nd compaction on; never mid-task.

## Stack defaults (assume, don't ask)
- Java: Maven multi-module (`mono-quarkus`), Quarkus + Spring Boot mix, OpenShift target.
- DB: PostgreSQL + Flyway, local dev DBs only, run migrations only when asked.
- Frontend: Angular. Shell: zsh, macOS or Ubuntu/Debian VM — no bash-only syntax unless asked.
- Python uv-workspace: scope `pytest` to the package dir, not repo root.
- Test DB: separate schema in the same db (`grocery_test`, `academy_test`); query
  `<schema>.<table>`; `mvn test` doesn't rebuild the schema — use `recreate-test-db.sh` after
  migration/seed changes (see `patterns/pre-prod-schema-folding.md`).

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
`memory/INDEX.md` lists every note; open only what matches. File new learnings by reuse:
- Library/framework/version quirk → `~/.claude/memory/libs/<lib-version>.md`
- Reusable design pattern → `~/.claude/memory/patterns/<name>.md`
- Repo-only facts → repo `.claude/memory/<topic>.md`, linking to the global note.
- Session record → `~/.claude/memory/sessions/<yyyy-mm-dd>-<topic>.md`; list in `MANIFEST`.
Add new notes to `memory/INDEX.md`. Concise, copy-pasteable; no local paths or credentials; no
raw decompiled output.

Rules (read before the task): config sync → `rules/config-sync.md` · audits/permission scans →
`rules/session-scans.md` · commit/push/PR → `rules/git-prs.md`.

## psql
- Read-only (SELECT/EXPLAIN/SHOW) → `bash ~/.claude/skills/psql-select/select.sh "<sql>"` or
  `select.sh <db> "<sql>"`; one `-c`, one statement; never set `PGPASSWORD`. Plain
  `psql -h localhost` only for INSERT/UPDATE/DELETE/DDL on the local dev DB; non-local hosts
  prompt; dropping `prore`/`prore_test` is denied.

## Git / PRs (full rules in `rules/git-prs.md`)
- Before new work: `bash ~/.claude/skills/pr-squash-sync/sync-check.sh <default>`; branch
  already squash-merged → new branch from `origin/<default>`.
- Before committing/pushing to an existing branch, check its PR isn't merged
  (`gh pr list --head <branch> --state all --json state`); merged → `pr-squash-sync` skill.
- Commit attribution: exactly one trailer `Co-Authored-By: Claude <noreply@anthropic.com>`
  (via `attribution.commit`); nothing else. PR descriptions: none.
- Squash to one commit (1–2 max) before a PR; "pr"/"squash pr" is the go-ahead. Never
  force-push `main`/`master`.

## Auth/role tests
- REST Assured first (`patterns/rest-assured-csv-role-matrix.md`); confirm roles per test user
  via `select.sh` and the endpoint's `@RolesAllowed`/`@PermitAll`; never assume seed ids.

## Don't (full list: `rules/conventions-detail.md`)
- No `cd x &&` prefixes (cwd persists); plain `git …` in the current repo; Maven `-pl <module> -am`
  from the root; `npm --prefix`/`ng`/`pytest <dir>` take a path.
- One command per Bash call — no `;`/`&&`/`|` chains; parallel calls when independent. Put "one
  command per call, no chaining, Read not `sed -n`" in every ad hoc agent prompt.
- No `sed -i` / `cat > f` / heredoc writes — use `Edit`/`Write`. No inline `python3` heredocs:
  script in scratchpad + `python3 -I`, or `jq`.
- Skill scripts: `bash ~/.claude/skills/<skill>/<script>.sh` — always `~/.claude/…`, never
  `$HOME` or `/home/…`. `test.sh` takes only `[<module> [Class]]`; `--summary` is `verify.sh` only.
- Skill logs live in `<project>/.claude/logs/<skill>.log`, never `/tmp`. Exclude `node_modules`
  from `find`/`grep`.
- `rm`/`mv`/`cp` denied: `git rm`/`git mv`, else `guarded-fs.sh rm|mv|cp`. `sudo`/`curl`/`wget`/
  `ssh`/destructive git: ask the user to run them.
- `.claude/memory/**` tracking edits: one row/block per `Edit`; if denied, mark BLOCKED and continue.
- No comments restating obvious code; no unrequested README/docs; no `--legacy-peer-deps` on
  auth/crypto/http-client packages — pin a compatible version.
