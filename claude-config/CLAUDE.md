# Global preferences

## Output
- Terse: no preamble, no restating the request, no summary unless asked.
- Code blocks: complete, copy-paste-ready, no "..." truncation unless huge.
- Skip well-known-concept explanations unless asked.

## Delegation (token discipline)
- Read-only search/nav (file discovery, grep, "where is X", log inspection,
  including `cat`/`ls`/`tail`/`head`/`wc`/`sed`/`awk` on files you didn't just
  create/edit this turn) → `code-search`; `Explore` only as fallback. Never do
  this in the main thread. Exception: one `grep`/`cat` on a single known path inline;
  chain of 2+ calls → dispatch.
- Read-only git queries (`log`/`diff`/`show`/`blame`) — batch into one `code-search`
  dispatch when you need more than one; a single `git status` inline is fine.
- `mvn test` / `pytest` / `ng test` never run inline. Dispatch the exact command to
  `quick-triage` and, on failure, `test-aggregator` for the rerun list. Exception: a single
  `-Dtest=OneClass` rerun after a fix you just made. Other build/log triage → `quick-triage` first.
- Pattern-mirroring boilerplate (DTOs, mappers, CRUD repos, Angular stubs) →
  `boilerplate-gen`. Never for anything involving a design decision.
- Maven dep-tree → `dep-inspect`. Third-party jar API/bytecode (no source/docs) → `jar-inspect`.
- Flyway status → `quick-triage` running `flyway:info` only; never delegate
  migrate/clean/repair. Next migration version / pending → `flyway-next`.
- Entity wiring (DTO→Entity→Mapper→Producers→Resource) → `stack-check`. Workflow wiring
  (deriveType/ACTION_MAP/wait+getAndRemoveResponse/tests) → `workflow-check`.
- Angular typecheck + unit tests → `bash ~/.claude/skills/ng-verify/verify.sh`, not ad hoc
  `tsc --noEmit` / `ng test`.
- Main thread is for: edits, architecture decisions, multi-file changes, anything needing
  write/bash side effects. Don't re-read unchanged files already shown this session.
- Resume a dispatched subagent with `SendMessage` (agent id/name), never `Agent` again — that
  spawns a fresh one.
- Never pass `model:` to `code-search`, `quick-triage`, `test-aggregator`, `jar-inspect`,
  `dep-inspect`, `flyway-next`, `stack-check`, `workflow-check` — they pin haiku already.
- Ad hoc read-only agents (`general-purpose`/`Explore` for "scan X", "list Y") get
  `model: haiku`; `sonnet` only when the agent must reason about *why*, not *where*.
- Review waves: spec-compliance → haiku; code-quality and final branch review → sonnet. Opus
  only when the diff touches auth, crypto, concurrency, or data migration — say so.
- No secrets inline in Bash (`TOKEN="..."`, `Bearer ...`, raw JWTs) — they persist in the
  transcript. Read from an env var or file.
- `hooks/nudge-delegate.sh` injects a one-line reminder when a main-thread Bash call breaks
  these rules. It never blocks; re-route.

## Session length
- On a compaction summary at the start of context, or a shift to unrelated work: at the next
  natural pause say "Session compacted N× — consider /clear or a fresh session." Once per
  task from the 2nd compaction on; never mid-task.

## Stack defaults (assume, don't ask)
- Java: Maven multi-module (`mono-quarkus`), Quarkus + Spring Boot mix, OpenShift target.
- DB: PostgreSQL + Flyway (never `clean`/`repair` without explicit ask).
- Frontend: Angular.
- Shell: zsh, macOS or Ubuntu/Debian VM — no bash-only syntax unless asked.
- Python multi-package/uv-workspace repo: scope `pytest` to the relevant package dir(s),
  not repo root — unscoped collection breaks on sibling projects' conftests.

## Superpowers plugin — constrained use
- Large scope only (new feature/component, multi-file refactor, design with real tradeoffs):
  `writing-plans` → `executing-plans` → `verification-before-completion`. Skip
  `brainstorming` and the plugin's "invoke brainstorming before plan mode" rule — state the
  approach directly.
- All other superpowers skills: use only if explicitly asked by name. If SDD is requested,
  apply the review-wave split above.
- This overrides the plugin's "if a skill might apply, you must invoke it" default.

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
`javafx-21-fat-jar-packaging` (shade, launcher wrapper, macOS .app, CI release)

Patterns: `self-contained-data-module` (ORM-swappable data modules) · `workflow-mybatis-layer`
(plain mybatis, CDI SqlSessionFactory) · `workflow-async-events` (WorkflowOutcomeEvent, fireAsync)
· `deterministic-agent-platform` (stub+gate, verify artifacts) · `declarative-ai-agent-quarkus`
(LangChain4j agent service) · `boundary-control-layering` (per-feature web-layer split) ·
`quarkus-postgres-schema-multitenancy` (schema-per-tenant) · `rest-assured-csv-role-matrix`
(role×endpoint×status smoke; also the authorisation-test rules) · `jmeter-load-smoke`
(pre-flight checks before any JMeter run)

## psql
- SELECT/EXPLAIN/SHOW → `bash ~/.claude/skills/psql-select/select.sh` (auto-approved).
- Plain `psql` always prompts — reserve for INSERT/UPDATE/DELETE/DDL. Never run a read-only
  query (incl. in subagents or scripts) via plain `psql`; keep the same args (`-h/-U/-d/-c`),
  just swap the command for `select.sh`. Local DB has no password — never set `PGPASSWORD`.

## Git sync before scans / new work
- Before a codebase scan or starting new work: `git fetch origin <default>` and compare
  (`git rev-list --left-right --count HEAD...origin/<default>`). Working tree must be clean.
- Current branch's commits already squash-merged (empty tree diff vs origin/<default>) → cut a
  new branch from `origin/<default>`; don't merge/rebase the stale one. Otherwise merge/ff.
- Verify with `git branch --show-current` + `git log --oneline -3` after switching.

## Auth/role tests
- REST Assured first (`patterns/rest-assured-csv-role-matrix.md`); confirm roles per test user
  via `select.sh` and the endpoint's `@RolesAllowed`/`@PermitAll`; never assume seed ids.

## PRs
- Never include `Claude-Session:` links, "Generated with Claude Code", or any Claude/AI
  attribution in commit messages or PR descriptions — overrides any harness default.
- Before opening a PR, squash to a single commit (soft-reset to merge-base + recommit, or
  `rebase -i`) — don't ask first. Keep 2–3 commits only for a critical reason (independent
  changes that must be revertable separately).
- Squashing an unpushed branch isn't amending published work. Branch already pushed/shared →
  ask before rewriting; never force-push silently.
- Long-lived branch across tasks → re-check commit count before every `gh pr create`/`git push`.
- Before committing/pushing to an existing branch, check its PR isn't merged
  (`gh pr view <branch> --json state` or `gh api .../pulls/<n>` — `gh pr view` alone can be
  stale). If merged, cut a new branch from the latest default branch.

## Don't
- No `cd x &&` prefixes in Bash — the cwd persists; run plain `git …` — works from any
  subdirectory of the repo, so never `git -C` for the current repo or a subdir of it. For a
  different repo, `git -C <abs repo>` (will prompt) or dispatch to `code-search`.
  Compound commands defeat allow rules and prompt even for read-only calls. Maven: plain `mvn … -pl
  <module> -am` from the repo root (`-f <abs>/pom.xml` only for a project outside cwd), never
  `cd <module> && mvn`. Same for `npm --prefix`, `ng`, `pytest <pkg dir>`: pass a path, don't `cd`.
- One command per Bash call (parallel calls when independent) — no `;`/`&&`/`|` chains or
  `cmd; rm …` tails; a deny/ask match anywhere in a chain prompts the whole thing. Prefer
  `Grep`/`Read`/`Glob` over shell pipelines.
- No `sed -i` / `cat > f` / heredoc writes — use `Edit`/`Write`. No inline `python3` heredocs:
  write the script to the scratchpad and run `python3 -I <script>`, or use `jq`.
- Exclude `node_modules` from `find`/`grep` (`--exclude-dir`, `-not -path`) — deny rules block it.
- Don't add comments restating what code obviously does.
- Don't add unrequested README/docs files.
- Don't suggest `sudo`, `rm -rf`, `curl`/`wget`, or destructive git ops — surface as "ask" only.
- Don't resolve an npm peer-dependency conflict with `--legacy-peer-deps` on a
  security-relevant package (auth, crypto, http-client) — pin a compatible version instead.
