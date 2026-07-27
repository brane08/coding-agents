# Global preferences

## Output
- Terse. No preamble, no restating the request, no summary unless asked.
- Code blocks: complete, copy-paste-ready. No "..." truncation unless file is huge.
- Skip explanations of well-known concepts unless asked.

## Delegation (token discipline)
- For read-only codebase search/navigation, prefer the custom `code-search`
  subagent over the built-in `Explore` — it has stack-specific rules (Maven
  module boundaries, Angular path conventions). Fall back to `Explore` only
  if `code-search` is unavailable.
- For build/test output and log triage, use the custom `quick-triage`
  subagent before deciding whether to escalate to Sonnet/Opus.
- For boilerplate that mirrors an existing pattern (DTOs, mappers, simple
  CRUD repos, Angular service/component stubs), use the custom
  `boilerplate-gen` subagent. Never use it when a design decision is
  involved — only for mechanical pattern-copying.
- For Maven dependency tree questions (what pulls in X, version conflicts,
  transitive deps), use the custom `dep-inspect` subagent instead of running
  `mvn dependency:tree` directly in the main thread.
- For Flyway migration status checks (pending vs. applied), use the custom
  `quick-triage` subagent running `flyway:info` only — never delegate
  `migrate`, `clean`, or `repair` to a subagent.
- Never do file discovery, grep/search, "where is X", dependency tracing, or
  log inspection directly in the main thread — always delegate.
- Reserve main-thread reasoning for: edits, architecture decisions, multi-file
  changes, anything requiring write/bash side effects.
- Don't re-read files already shown in this session unless they changed.

## Stack defaults (skip asking, just assume)
- Java: Maven multi-module (`mono-quarkus`), Quarkus + Spring Boot mix, OpenShift target.
- DB: PostgreSQL, Flyway migrations (never suggest `flyway:clean`/`repair` without explicit ask).
- Frontend: Angular.
- Shell: zsh, macOS or Ubuntu/Debian VM. Don't suggest bash-specific syntax unless asked.

## Memory
Before analyzing any library, JAR, framework class, or internal implementation detail:
1. Check `~/.claude/memory/libs/` (below) for cross-project library/framework notes.
2. Check `.claude/memory/` in the current repo for project-specific notes.
3. Only open JARs, decompile, or fetch docs if neither has the answer.

After learning something new, file it by reuse, not by where it was learned:
- Library, framework, version quirk, JPMS rule, working config → `~/.claude/memory/libs/<lib-version>.md`
- Reusable design pattern → `~/.claude/memory/patterns/<name>.md`
- Only repo-specific facts (that project's names, paths, wiring) → repo `.claude/memory/<topic>.md`,
  linking out to the global note instead of restating it.

Keep entries concise and copy-pasteable; no local paths or credentials; never dump raw decompiled output.

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

## psql
- For SELECT/EXPLAIN/SHOW queries use `bash ~/.claude/skills/psql-select/select.sh` (auto-approved).
- Plain `psql` always prompts — reserve it for INSERT/UPDATE/DELETE/DDL.

## Don't
- Don't add comments restating what code obviously does.
- Don't add unrequested README/docs files.
- Don't suggest `sudo`, `rm -rf`, `curl`/`wget`, or destructive git ops — surface as "ask" only.
