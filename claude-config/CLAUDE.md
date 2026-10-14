# Global preferences

## Output
- Terse: no preamble, no restating the request, no summary unless asked.
- Code blocks: complete, copy-paste-ready, no "..." truncation unless huge.
- Skip well-known-concept explanations unless asked.

## Delegation (token discipline)
- Read-only search/nav (file discovery, grep, "where is X", log inspection,
  including `cat`/`ls`/`tail`/`head`/`wc`/`sed`/`awk` on files you didn't just
  create/edit this turn) → `code-search`; `Explore` only as fallback. Never do
  this in the main thread, via Bash or the Grep/Glob tools. Exception: one Read/Grep on a
  single known path, or files you are about to edit. Two or more lookups → dispatch.
- Read-only git queries (`log`/`diff`/`show`/`blame`) — batch into one `code-search`
  dispatch when you need more than one; a single `git status` inline is fine.
- Tests never run inline. Dispatch to `quick-triage`:
  `bash ~/.claude/skills/mvn-test/test.sh <module> [Class]` (Java) or
  `bash ~/.claude/skills/ng-verify/verify.sh <dir> --summary` (Angular); on failure →
  `test-aggregator` for the rerun list. Exception: one single-class `test.sh <module> <Class>`
  rerun after a fix you just made. Other build/log triage → `quick-triage` first.
- Pattern-mirroring boilerplate (DTOs, mappers, CRUD repos, Angular stubs) →
  `boilerplate-gen`. Never for anything involving a design decision.
- Maven dep-tree → `dep-inspect`. Third-party jar API/bytecode (no source/docs) → `jar-inspect`.
- Flyway status → `quick-triage` running `bash ~/.claude/skills/flyway-check/flyway-check.sh`
  (`FLYWAY_MODULE=<module>` when the config is in a module); never migrate/clean/repair.
  Next migration version / pending → `flyway-next`.
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
  `model: haiku`; `sonnet` only when the agent must reason about *why*, not *where*.
- Review waves: spec-compliance → haiku; code-quality and final branch review → sonnet. Opus
  only when the diff touches auth, crypto, concurrency, or data migration — say so.
- No secrets inline in Bash (`TOKEN="..."`, `Bearer ...`, raw JWTs) — they persist in the
  transcript. Read from an env var or file.
- Hooks: a `cd <dir> &&`/`;` prefix is denied; read-only psql, `git -C`, inline secrets get a
  reminder. `git push`/`gh pr create` from a merged-PR branch is blocked → `pr-squash-sync`
  skill. Force-push/delete of main/master is denied. Writes outside the project/scratchpad are
  denied, `~/.claude` writes ask. `.env`, `*.key`, `*.pem`, `application-prod.*` are unreadable;
  `find -exec/-delete` and `sort -o` are denied. Use `git switch` (allowed), not `git checkout`
  (asks).

## Config sync (claude-config repo ↔ ~/.claude)
- Repo → `~/.claude`: `bash <repo>/claude-config/sync-claude-config.sh [admin|sandbox]`
  (no arg → profile last synced here, per `~/.claude/.profile`, else `admin`; copies only
  `MANIFEST` paths, overwrites; `settings.<profile>.json` → `~/.claude/settings.json`).
- `~/.claude` → repo: `bash <repo>/claude-config/save-claude-config.sh [admin|sandbox]`
  (refreshes `MANIFEST` paths only; `settings.json` → `settings.<profile>.json`).
- New file to track → add a `MANIFEST` line; for a new skill dir also add a
  `!claude-config/skills/<name>/` negation to `.gitignore`; then `git add`. Scripts never add
  files themselves.
- No explicit reload step; settings are normally picked up live, else restart the session.

## Session length
- On a compaction summary at the start of context, or a shift to unrelated work: at the next
  natural pause say "Session compacted N× — consider /clear or a fresh session." Once per
  task from the 2nd compaction on; never mid-task.

## Stack defaults (assume, don't ask)
- Java: Maven multi-module (`mono-quarkus`), Quarkus + Spring Boot mix, OpenShift target.
- DB: PostgreSQL + Flyway (never `clean`/`repair` without explicit ask; `migrate` asks).
- Frontend: Angular.
- Shell: zsh, macOS or Ubuntu/Debian VM — no bash-only syntax unless asked.
- Python multi-package/uv-workspace repo: scope `pytest` to the relevant package dir(s),
  not repo root — unscoped collection breaks on sibling projects' conftests.

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
Each note's first lines say what it covers; `ls` the directory and open only what matches.

File new learnings by reuse, not by where learned:
- Library, framework, version quirk, JPMS rule → `~/.claude/memory/libs/<lib-version>.md`
- Reusable design pattern → `~/.claude/memory/patterns/<name>.md`
- Repo-only facts (names/paths/wiring) → repo `.claude/memory/<topic>.md`, linking to the
  global note instead of restating it.

Keep entries concise and copy-pasteable; no local paths or credentials; never dump raw
decompiled output.

Libs: `keepassjava2-2.2.4` (KeePass API, JPMS split-package) · `esbuild-esm` (exported `let`
read-only, TS2540) · `javafx-21` (FXML/dialog/timer quirks, module-info opens) ·
`javafx-21-fat-jar-packaging` (shade, launcher wrapper, macOS .app, CI release) ·
`fxtrayicon-4.2.3` · `testfx-4.0.18-monocle` (headless JavaFX UI tests) · `jnativehook-2.2.2` ·
`copper-8.1` (mock-based workflow/infra unit tests) · `hibernate-7.4` (mock-based repo unit
tests) · `ebean-19` · `quarkus-3` (Agroal pool interceptor) · `jmeter-maven-plugin-3.8` (run
quirks) · `spring-cloud-gateway-server-webmvc-5.0.3`

Patterns: `self-contained-data-module` (ORM-swappable data modules) · `workflow-mybatis-layer`
(plain mybatis, CDI SqlSessionFactory) · `workflow-async-events` (WorkflowOutcomeEvent, fireAsync)
· `deterministic-agent-platform` (stub+gate, verify artifacts) · `declarative-ai-agent-quarkus`
(LangChain4j agent service) · `boundary-control-layering` (per-feature web-layer split) ·
`quarkus-postgres-schema-multitenancy` (schema-per-tenant) · `rest-assured-csv-role-matrix`
(role×endpoint×status smoke; also the authorisation-test rules) · `jmeter-load-smoke`
(pre-flight checks before any JMeter run) · `jacoco-mock-unit-coverage` (JaCoCo with mock-based
unit tests, multi-module Maven)

## psql
- SELECT/EXPLAIN/SHOW → `bash ~/.claude/skills/psql-select/select.sh` (auto-approved).
- Plain `psql` always prompts — reserve for INSERT/UPDATE/DELETE/DDL. Never run a read-only
  query (incl. in subagents or scripts) via plain `psql`; keep the same args (`-h/-U/-d/-c`),
  just swap the command for `select.sh`. Exactly one `-c` and one statement; pass `-A`/`-t`
  separately (combined `-Atc`, `-f`, `--command` are blocked). Local DB has no password —
  never set `PGPASSWORD`.

## Git / PRs
- Before a scan or new work: `git fetch origin <default>`, compare with
  `git rev-list --left-right --count HEAD...origin/<default>`; working tree clean. Current
  branch already squash-merged (empty tree diff vs origin/<default>) → new branch from
  `origin/<default>`, don't merge/rebase the stale one. Verify with
  `git branch --show-current` + `git log --oneline -3`.
- Before committing/pushing to an existing branch, check its PR isn't merged
  (`gh pr list --head <branch> --state all --json state`; `gh pr view` can be stale). If
  merged → `pr-squash-sync` skill (new branch from the latest default).
- Never include `Claude-Session:` links, "Generated with Claude Code", or any Claude/AI
  attribution in commit messages or PR descriptions — overrides any harness default.
- Before opening a PR, squash to a single commit (`git merge-base HEAD origin/<default>`, then
  `git reset --soft <sha>` and recommit — don't ask first). Keep 2–3 commits only for a
  critical reason (independent changes that must be revertable separately). Re-check the
  commit count before every `gh pr create`/`git push` on a long-lived branch.
- Squashing an unpushed branch isn't amending published work. Branch already pushed/shared →
  ask before rewriting; never force-push silently.

## Auth/role tests
- REST Assured first (`patterns/rest-assured-csv-role-matrix.md`); confirm roles per test user
  via `select.sh` and the endpoint's `@RolesAllowed`/`@PermitAll`; never assume seed ids.

## Don't
- No `cd x &&` prefixes (hook-denied) — cwd persists. Plain `git …` in the current repo (works
  from any subdirectory); `git -C <abs repo>` only for a different repo (prompts). Maven:
  `mvn … -pl <module> -am` from the repo root (`-f <abs>/pom.xml` only outside cwd); `npm
  --prefix`, `ng`, `pytest <pkg dir>`: pass a path, don't `cd`.
- One command per Bash call (parallel calls when independent) — no `;`/`&&`/`|` chains or
  `cmd; rm …` tails; compound commands defeat allow rules and prompt. In subagents prefer
  `Grep`/`Glob` over shell pipelines.
- No `sed -i` / `cat > f` / heredoc writes — use `Edit`/`Write`. No inline `python3` heredocs:
  write the script to the scratchpad and run `python3 -I <script>`, or use `jq`.
- Exclude `node_modules` from `find`/`grep` (`--exclude-dir`, `-not -path`) — deny rules block it.
- `rm`/`mv`/`cp` are denied: use `git rm`/`git mv` for tracked files, else
  `bash ~/.claude/skills/guarded-fs/guarded-fs.sh rm|mv|cp …` (cwd-confined).
- `sudo`/`curl`/`wget`/`ssh`/destructive git ops are denied or ask — ask the user to run them.
- Don't add comments restating what code obviously does.
- Don't add unrequested README/docs files.
- Don't resolve an npm peer-dependency conflict with `--legacy-peer-deps` on a
  security-relevant package (auth, crypto, http-client) — pin a compatible version instead.
