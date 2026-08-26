# Global preferences

## Output
- Terse. No preamble, no restatement, no summary unless asked.
- Code blocks: complete, copy-paste-ready. No truncation unless file is huge.
- Skip well-known concept explanations unless asked.
- No emojis unless asked.

## Planning
- Plan first only for large/risky changes: schema/API/contract, architecture, auth/security/data-integrity.
- Everything else: proceed directly, even multi-file edits.
- Wait for plan approval before coding (large/risky only).
- One clarifying question at a time.

## Superpowers
- Use only for large/risky changes (same threshold as Planning).
- Prefer `executing-plans` over `subagent-driven-development` unless parallelism is needed.
- Request smaller task chunks if default sizing is too coarse/granular.

## Delegation
- Read-only search/navigation → `code-search` subagent (stack-aware). Fall back to `Explore` only if unavailable.
- Build/test/log triage → `quick-triage` subagent.
- Boilerplate mirroring existing pattern → `boilerplate-gen` subagent. Never when design decisions involved.
- Maven dependency questions → `dep-inspect` subagent.
- Flyway status → `quick-triage` running `flyway:info` only. Never delegate `migrate`/`clean`/`repair`.
- Next migration version / pending migrations → `flyway-next` subagent.
- Entity wiring completeness (DTO→Entity→Mapper→Producers→Resource) → `stack-check` subagent.
- Workflow wiring completeness (deriveType/ACTION_MAP/wait+getAndRemoveResponse/tests) → `workflow-check` subagent.
- Test failure summary after a build → `test-aggregator` subagent (parses surefire XML, returns rerun commands per failing test).
- Never grep/search/discover files in main thread — always delegate.
- Main thread: edits, architecture decisions, write/bash side effects only.
- Don't re-read files already shown this session unless changed.
- Unknown or likely large files (>200 lines): delegate to `code-search` with a targeted question; don't Read whole file in main thread.
- Grep before Read: when locating a symbol/pattern, grep for the exact line first, then Read only that range.

## Agentic design
- LangGraph/LangChain: typed state (Pydantic/TypedDict), explicit tool schemas, idempotent nodes.
- MCP/FastMCP: minimal tool surface, one job per tool, unit-testable outside runtime. Default read-only.
- No-match routing = explicit error, never silent fallback.

## Stack defaults
- Java: Maven multi-module, Quarkus + Spring Boot mix, OpenShift target.
- DB: PostgreSQL, Flyway (never suggest `clean`/`repair` without explicit ask).
- Frontend: Angular.
- Shell: zsh, macOS or Ubuntu/Debian VM — no bash-only syntax unless asked.

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

## psql
- SELECT/EXPLAIN/SHOW → `bash ~/.claude/skills/psql-select/select.sh` (auto-approved).
- Plain `psql` always prompts — reserve for INSERT/UPDATE/DELETE/DDL.

## PRs
- Before opening a PR, squash to 1-5 logical commits since the base-branch divergence
  (soft-reset to merge-base + recommit, or `rebase -i`) — don't ask first.
- Squashing an unpushed/unshared branch isn't amending published work — the
  never-amend rule protects pushed history, not commit count on a fresh branch.
- Branch already pushed and possibly shared → ask before rewriting; never force-push
  silently.

## Don't
- No comments restating obvious code.
- No unrequested README/docs.
- No `sudo`, `rm -rf`, `curl`/`wget`, destructive git ops — surface as "ask" only.

## Diff discipline
- Edit, don't rewrite. Targeted edits only; never regenerate whole files.
- Touch only what the task requires. No drive-by reformatting/renaming/cleanup.
- Match existing style exactly.
- No unrequested refactors bundled into feature/fix changes.
- Preserve unrelated whitespace/line-endings.

## Memory
- Concise notes only, no large pasted blocks.
