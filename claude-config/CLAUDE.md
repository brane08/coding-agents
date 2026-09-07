# Global preferences

## Output
- Terse: no preamble, no restating the request, no summary unless asked.
- Code blocks: complete, copy-paste-ready, no "..." truncation unless huge.
- Skip well-known-concept explanations unless asked.

## Delegation (token discipline)
- Read-only search/nav (file discovery, grep, "where is X", log inspection) →
  `code-search`; `Explore` only as fallback. Never do this in the main thread.
- Build/test/log triage → `quick-triage` before escalating to Sonnet/Opus.
- Pattern-mirroring boilerplate (DTOs, mappers, CRUD repos, Angular stubs) →
  `boilerplate-gen`. Never for anything involving a design decision.
- Maven dep-tree questions → `dep-inspect`, not `mvn dependency:tree` inline.
- Third-party jar API/bytecode inspection (no source/docs available) →
  `jar-inspect`, not ad hoc `unzip`/`javap` inline.
- Flyway status → `quick-triage` running `flyway:info` only; never delegate
  migrate/clean/repair.
- Next migration version / pending migrations → `flyway-next`.
- Entity wiring completeness (DTO→Entity→Mapper→Producers→Resource) → `stack-check`.
- Workflow wiring completeness (deriveType/ACTION_MAP/wait+getAndRemoveResponse/tests) →
  `workflow-check`.
- Test failure summary after a build → `test-aggregator` (parses surefire XML, returns
  rerun commands per failing test).
- Angular typecheck + unit tests → `bash ~/.claude/skills/ng-verify/verify.sh`, not
  ad hoc `tsc --noEmit` / `ng test` inline.
- Main-thread reasoning is for: edits, architecture decisions, multi-file changes, and
  anything needing write/bash side effects.
- Don't re-read unchanged files already shown this session.
- To resume a previously-dispatched subagent, use `SendMessage` with its agent id/name —
  never the `Agent` tool again, which silently spawns a fresh one instead of continuing it.

## Stack defaults (assume, don't ask)
- Java: Maven multi-module (`mono-quarkus`), Quarkus + Spring Boot mix, OpenShift target.
- DB: PostgreSQL + Flyway (never `clean`/`repair` without explicit ask).
- Frontend: Angular.
- Shell: zsh, macOS or Ubuntu/Debian VM — no bash-only syntax unless asked.
- Python multi-package/uv-workspace repo: scope `pytest` to the relevant package dir(s),
  not repo root — unscoped collection breaks on unrelated sibling projects' conftests
  (same instinct as module-scoped Maven builds).

## Superpowers plugin — constrained use
- Large scope only: a new feature/component, a multi-file refactor, or a design decision
  with real tradeoffs. NOT a single-file edit, config/settings tweak, doc update, small
  bugfix, or anything answerable directly.
- On large scope, use only this minimal stage set, in order: `writing-plans` →
  `executing-plans` → `verification-before-completion`. Skip `brainstorming` — state
  the approach directly instead of invoking it.
- All other superpowers skills (`brainstorming`, `subagent-driven-development`,
  `dispatching-parallel-agents`, `test-driven-development`, `systematic-debugging`,
  `requesting-code-review`, `receiving-code-review`, `finishing-a-development-branch`,
  `using-git-worktrees`, `writing-skills`) are available but not auto-invoked — use only
  if explicitly asked by name.
- This overrides the plugin's own "if a skill might apply, you must invoke it" default —
  that default does not apply outside the large-scope + core-3 case above.

## Tooling gotchas
- `EnterWorktree` branches from `origin/<default-branch>` by default, not your current
  branch — pass the base explicitly if supported, or `git worktree add <path> -b
  <branch> <base>` manually, and verify with `git branch --show-current`/`git log`
  right after entering.

## Memory
Before analyzing a library/JAR/framework/internal detail: check `~/.claude/memory/libs/`,
then repo `.claude/memory/`, then decompile/fetch docs only if neither answers it.

File new learnings by reuse, not by where learned:
- Library, framework, version quirk, JPMS rule → `~/.claude/memory/libs/<lib-version>.md`
- Reusable design pattern → `~/.claude/memory/patterns/<name>.md`
- Repo-only facts (names/paths/wiring) → repo `.claude/memory/<topic>.md`, linking to the
  global note instead of restating it.

Keep entries concise and copy-pasteable; no local paths or credentials; never dump raw
decompiled output.

| File | Covers |
|------|--------|
| `libs/keepassjava2-2.2.4.md` | KeePassJava2 2.2.4 — create/open/save, entry CRUD, groups, timestamps, `getNotes()` null-guard, JPMS split-package/`Automatic-Module-Name` workaround |
| `libs/javafx-21.md` | JavaFX 21 — FXML accelerators broken, `showAndWait()` in animation callbacks, `PauseTransition` quirks, `FXMLLoader` init-vs-injection ordering, controller-less FXML + `lookup()`, password show/hide, dialog validation, idle timer, `module-info` opens rules |
| `libs/javafx-21-fat-jar-packaging.md` | JavaFX fat JAR — non-`Application` launcher wrapper, `module-info.class` shade exclusion, platform classifier profiles, required `--add-opens`/`--enable-native-access`, macOS `.app` + assembly `fileMode`, shade-before-assembly ordering, tag-triggered CI release, SVG→icns |

## Architecture patterns
Saved patterns live in `~/.claude/memory/patterns/`. Check these before designing a solution:

| File | Pattern |
|------|---------|
| `self-contained-data-module.md` | ORM-swappable data modules — CDI producers live inside the data module, repositories never exposed as CDI beans, swap = one pom.xml line |
| `workflow-mybatis-layer.md` | Workflow data layer — plain mybatis jar (not quarkus-mybatis), CDI SqlSessionFactory producer from Agroal DataSource, mapper interfaces registered programmatically; result_payload column for replay identification |
| `workflow-async-events.md` | Workflow outcome delivery — workflow publishes WorkflowOutcomeEvent via SPI, CDI fireAsync() in monolith, @ObservesAsync @Transactional consumer does domain writes; swap path to Kafka = one file change |
| `deterministic-agent-platform.md` | Meta-agent / catalog-platform — seam+deterministic stub for credential-free CI, stub can't spoof its own gate, verify artifacts not agent claims, publish-only-on-success, tier ledger latest-per-key (not min()), recall≠no-record, length-prefixed hashing, role separation as anti-drift |
| `declarative-ai-agent-quarkus.md` | LLM chat/tool-calling agent as its own Quarkus service — LangChain4j `@RegisterAiService` declarative interface, tools as plain CDI `@Tool` beans, `@RequestScoped` context bean for threading userId/role into tools, swappable session-keyed `ChatMemoryProvider`, fail-soft fallback at both service and bridge layers, `@InjectMock` the generated AI service + WireMock the HTTP bridge for tests |
| `boundary-control-layering.md` | Per-feature web-layer package split — `.boundary` (Controller/Resource/ExceptionMapper/Filter), `.control` (Service/Job), `.entity` (request-scoped context, not JPA); apply selectively (CRUD-only features get `.boundary` only), don't force onto non-HTTP modules (workflow engines, agent services keep their own layout) |
| `quarkus-postgres-schema-multitenancy.md` | Schema-per-tenant multi-tenancy (Quarkus + Postgres) — isolate tenants via Postgres schema instead of a `tenant_id` column |

## psql
- SELECT/EXPLAIN/SHOW → `bash ~/.claude/skills/psql-select/select.sh` (auto-approved).
- Plain `psql` always prompts — reserve for INSERT/UPDATE/DELETE/DDL.

## PRs
- Before opening a PR, squash to a single commit by default since the base-branch
  divergence (soft-reset to merge-base + recommit, or `rebase -i`) — don't ask first.
  Only leave more than 1 commit (max 3) when there's a critical reason to keep them
  separate (e.g. genuinely independent changes that must be revertable on their own).
- Squashing an unpushed branch isn't amending published work — never-amend protects
  pushed history, not commit count on a fresh branch.
- Branch already pushed/shared → ask before rewriting; never force-push silently.
- Long-lived branch across multiple tasks → re-check commit count before every
  `gh pr create`/`git push`, unprompted.

## Don't
- Don't add comments restating what code obviously does.
- Don't add unrequested README/docs files.
- Don't suggest `sudo`, `rm -rf`, `curl`/`wget`, or destructive git ops — surface as
  "ask" only.
- Don't resolve an npm peer-dependency conflict with `--legacy-peer-deps` on a
  security-relevant package (auth, crypto, http-client) — pin a compatible version
  instead.
