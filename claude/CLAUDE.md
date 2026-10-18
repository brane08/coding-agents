# Global preferences

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
  `bash ~/.claude/skills/ng-verify/verify.sh <dir> --summary` (Angular); on failure →
  `test-aggregator` for the rerun list. Exception: one single-class `test.sh <module> <Class>`
  rerun after a fix you just made. Other build/log triage → `quick-triage` first.
- Pattern-mirroring boilerplate (DTOs, mappers, CRUD repos, Angular stubs) →
  `boilerplate-gen`. Never for anything involving a design decision.
- Maven dep-tree → `dep-inspect`. Third-party jar API/bytecode (no source/docs) → `jar-inspect`.
- Flyway status → `quick-triage` running `bash ~/.claude/skills/flyway-check/flyway-check.sh`
  (`FLYWAY_MODULE=<module>` when the config is in a module); the status script is read-only —
  migrate/clean/repair only via explicit `mvn`/`mvnw flyway:*` on local dev DBs.
  Next migration version / pending / listing migrations → `flyway-next` (a listing is a Glob, not `ls`).
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
- Hooks: a `cd <dir> &&`/`;` prefix is denied; admin profile also denies the 7th consecutive
  lookup (Bash/Grep/Glob) with no Edit/Write/Agent between → one `code-search`; read-only psql, `git -C`, inline secrets get a
  reminder. `git push`/`gh pr create` from a merged-PR branch is blocked → `pr-squash-sync`
  skill. Force-push/delete of main/master is denied. Writes outside the project/scratchpad are
  denied; `~/.claude` is an additional directory (reads, greps and writes need no prompt). `.env`, `*.key`, `*.pem`, `application-prod.*` are unreadable;
  `find -exec/-delete` and `sort -o` are denied. Use `git switch` (allowed), not `git checkout`
  (asks).

## Config sync (claude repo ↔ ~/.claude)
- Repo → `~/.claude`: `bash <repo>/claude/sync-claude-config.sh [admin|sandbox]`
  (no arg → profile last synced here, per `~/.claude/.profile`, else `admin`; copies only
  `MANIFEST` paths, overwrites; `settings.<profile>.json` → `~/.claude/settings.json`).
- `~/.claude` → repo: `bash <repo>/claude/save-claude-config.sh [admin|sandbox]`
  (refreshes `MANIFEST` paths only; `settings.json` → `settings.<profile>.json`).
- New file to track → add a `MANIFEST` line; for a new skill dir also add a
  `!claude/skills/<name>/` negation to `.gitignore`; then `git add`. Scripts never add
  files themselves.
- `settings.*.json` stay key-sorted (`jq -S`): `save` sorts automatically. After hand-editing a
  repo copy, verify with `jq -S . <file> | diff - <file>` (empty = sorted). Keeps diffs to real
  changes, not reordering.
- No explicit reload step; settings are normally picked up live, else restart the session.

## Session length
- On a compaction summary at the start of context, or a shift to unrelated work: at the next
  natural pause say "Session compacted N× — consider /clear or a fresh session." Once per
  task from the 2nd compaction on; never mid-task.

## Session scans (history reviews)
- Run the scripts, don't hand-parse transcripts: `delegation-audit/audit.py --since <date>`
  (routing) and `delegation-audit/ctx.py` (context/compaction). Main-thread turns only
  (exclude sidechains); dedupe by message id.
- Permission prompts: `delegation-audit/permissions.py --since <date> [--profile both]` →
  report, and new allow/env entries written into repo `settings.<profile>.json` from the
  `log-ask.sh` log (`--dry-run` to preview); never add rules from memory of a prompt.
- Always report: window checked (dates, session count, per project); routing violation rate vs
  the last log entry; peak context + context at compaction + compactions per session + turns
  between compactions; turns/tokens per model (main vs subagents) with the share of
  mechanical-only turns (Bash/Grep/Glob/Read, no text) per model, and what could drop a tier
  (sonnet/opus subagent doing lookups → haiku; opus outside auth/crypto/concurrency/migration
  → sonnet); top 3 repeated shapes; which rules/hooks were changed since the last
  scan (so a rate change is attributable). Flag sessions open before the last config change.
- Before changing a window/autocompact/hook setting, state the measured number it targets.
  Log 2–3 lines in `~/.claude/memory/delegation-audit-log.md`; never paste raw output.
- Cost claims: separate cache-read from uncached tokens; say what was not measured (quality
  after compaction).

## Stack defaults (assume, don't ask)
- Java: Maven multi-module (`mono-quarkus`), Quarkus + Spring Boot mix, OpenShift target.
- DB: PostgreSQL + Flyway (all `mvn`/`mvnw flyway:*` goals incl. migrate/clean/repair are
  allowed without a prompt, local dev DBs only — never prod hosts/names; run only when asked).
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
- Working-session record (what changed, decisions, open items) → `~/.claude/memory/sessions/<yyyy-mm-dd>-<topic>.md`,
  linking to the libs/patterns notes for reusable facts; list it in `MANIFEST`.

Keep entries concise and copy-pasteable; no local paths or credentials; never dump raw
decompiled output.

Libs: `keepassjava2-2.2.4` (KeePass API, JPMS split-package) · `esbuild-esm` (exported `let`
read-only, TS2540) · `javafx-21` (FXML/dialog/timer quirks, module-info opens) ·
`javafx-21-fat-jar-packaging` (shade, launcher wrapper, macOS .app, CI release) ·
`fxtrayicon-4.2.3` · `testfx-4.0.18-monocle` (headless JavaFX UI tests) · `jnativehook-2.2.2` ·
`copper-8.1` (mock-based workflow/infra unit tests) · `hibernate-7.4` (mock-based repo unit
tests) · `ebean-19` · `quarkus-3` (Agroal pool interceptor) · `jmeter-maven-plugin-3.8` (run
quirks) · `spring-cloud-gateway-server-webmvc-5.0.3` · `claude-code-permissions` (prompts,
additionalDirectories, allow-rule matching, hooks)

Patterns: `tracking-pattern` (findings/items/decisions/reviews folder; DS/FE/BG/TS/DC/RV-nnn IDs;
states DOING·BLOCKED·PARTIAL·PENDING·BACKLOG·DEFERRED·DONE·WONT-DO; dated items; archive at 30
DONE) · `self-contained-data-module` (ORM-swappable data modules) · `workflow-mybatis-layer`
(plain mybatis, CDI SqlSessionFactory) · `workflow-async-events` (WorkflowOutcomeEvent, fireAsync)
· `deterministic-agent-platform` (stub+gate, verify artifacts) · `declarative-ai-agent-quarkus`
(LangChain4j agent service) · `boundary-control-layering` (per-feature web-layer split) ·
`quarkus-postgres-schema-multitenancy` (schema-per-tenant) · `rest-assured-csv-role-matrix`
(role×endpoint×status smoke; also the authorisation-test rules) · `jmeter-load-smoke`
(pre-flight checks before any JMeter run) · `jacoco-mock-unit-coverage` (JaCoCo with mock-based
unit tests, multi-module Maven) · `claude-config-repo-sync` (repo ↔ ~/.claude merge routine, dir rename)

## psql
- SELECT/EXPLAIN/SHOW → `bash ~/.claude/skills/psql-select/select.sh "<sql>"` (local Postgres:
  localhost, user postgres, db prore, `-A -t`) or `select.sh <db> "<sql>"` for another db
  (e.g. `prore_test`). The long `-h/-U/-d/-c` form still works for non-default hosts.
- Plain `psql` always prompts — reserve for INSERT/UPDATE/DELETE/DDL. Never run a read-only
  query (incl. in subagents or scripts) via plain `psql`; keep the same args (`-h/-U/-d/-c`),
  just swap the command for `select.sh`. Exactly one `-c` and one statement; pass `-A`/`-t`
  separately (combined `-Atc`, `-f`, `--command` are blocked). Local DB has no password —
  never set `PGPASSWORD`.

## Git / PRs
- Before a scan or new work: `bash ~/.claude/skills/pr-squash-sync/sync-check.sh <default>`
  (one call: fetch, branch, status, ahead/behind, tree diff, last 3 commits, PR states);
  working tree clean. Current branch already squash-merged (empty tree diff vs
  origin/<default>) → new branch from `origin/<default>`, don't merge/rebase the stale one.
  Verify after switching with the same script.
- Before committing/pushing to an existing branch, check its PR isn't merged
  (`gh pr list --head <branch> --state all --json state`; `gh pr view` can be stale). If
  merged → `pr-squash-sync` skill (new branch from the latest default).
- Never include `Claude-Session:` links, "Generated with Claude Code", or any Claude/AI
  attribution in commit messages or PR descriptions — overrides any harness default.
- Before opening a PR, squash to a single commit (`git merge-base HEAD origin/<default>`, then
  `git reset --soft <sha>` and recommit — don't ask first). A PR has 1–2 commits max; 2 only
  for independent changes that must be revertable separately. Re-check the commit count
  before every `gh pr create`/`git push` on a long-lived branch.
- Squashing an unpushed branch isn't amending published work. A "pr"/"squash pr" request is the
  go-ahead to squash: do it with no follow-up question, including amending your own pushed PR
  branch and `git push --force-with-lease`. Ask first only for a branch you didn't create or
  that others share; never force-push `main`/`master` or silently.

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
  `Grep`/`Glob` over shell pipelines. Put "one command per call, no chaining, Read not
  `sed -n`" in every ad hoc agent prompt.
- No `sed -i` / `cat > f` / `printf … >> f` / heredoc writes — use `Edit`/`Write` (append =
  Edit anchored on the file's last line). No inline `python3` heredocs:
  write the script to the scratchpad and run `python3 -I <script>`, or use `jq`.
- `.claude/memory/**` tracking edits: one row or block per `Edit`; multi-row edits trip the
  auto-mode classifier. If one is denied, say so and let the user approve — don't retry.
- Skill/hook scripts: `bash|zsh|ksh ~/.claude/skills/<skill>/<script>.sh …` (any of the three
  is allowed; scripts re-exec into their own shell). Always `~/.claude/…` — never `$HOME`,
  `/Users/…` or `/home/…`: allow rules only match `~`, a full path prompts or is blocked.
- `test.sh` takes only `[<module> [Class]]` (flags are rejected); `--summary` is `verify.sh` only.
- Exclude `node_modules` from `find`/`grep` (`--exclude-dir`, `-not -path`) — deny rules block it.
- `rm`/`mv`/`cp` are denied: use `git rm`/`git mv` for tracked files, else
  `bash ~/.claude/skills/guarded-fs/guarded-fs.sh rm|mv|cp …` (cwd-confined).
- `sudo`/`curl`/`wget`/`ssh`/destructive git ops are denied or ask — ask the user to run them.
- Don't add comments restating what code obviously does.
- Don't add unrequested README/docs files.
- Don't resolve an npm peer-dependency conflict with `--legacy-peer-deps` on a
  security-relevant package (auth, crypto, http-client) — pin a compatible version instead.
