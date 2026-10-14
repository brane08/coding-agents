# Global preferences

## Output
- Terse: no preamble, no restating the request, no summary unless asked.
- Code blocks: complete, copy-paste-ready, no "..." truncation unless huge.
- Skip well-known-concept explanations unless asked.

## Stack defaults (assume, don't ask)
- Java: Maven multi-module (`mono-quarkus`), Quarkus + Spring Boot mix, OpenShift target.
- DB: PostgreSQL + Flyway (never `clean`/`repair` without explicit ask).
- Frontend: Angular.
- Shell: zsh, macOS or Ubuntu/Debian VM — no bash-only syntax unless asked.
- Python multi-package/uv-workspace repo: scope `pytest` to the relevant package dir(s),
  not repo root — unscoped collection breaks on sibling projects' conftests.

## Helper scripts (`.github/skills/`)
- Angular typecheck + unit tests: `bash .github/skills/ng-verify/verify.sh <app-dir> --summary`, not ad hoc `tsc --noEmit` / `ng test`.
- Read-only SQL: `bash .github/skills/psql-select/select.sh -h/-U/-d … -c "<sql>"`. Exactly one `-c`, one statement; `-f`/`--command`/`-Atc` are blocked. Plain `psql` only for INSERT/UPDATE/DELETE/DDL. Local DB has no password — never set `PGPASSWORD`.
- Maven build/test/dev and Flyway status: `.github/skills/{mvn-build,mvn-test,quarkus-dev,flyway-check}/`.

## Memory
Before analyzing a library/JAR/framework/internal detail: check `.github/memory/libs/`
(global install: `~/.copilot/memory/libs/`), then repo-specific notes, then decompile/fetch docs only if neither answers it.
Each note's first lines say what it covers; list the directory and open only what matches.

File new learnings by reuse, not by where learned:
- Library, framework, version quirk, JPMS rule → `.github/memory/libs/<lib-version>.md`
- Reusable design pattern → `.github/memory/patterns/<name>.md`
- Repo-only facts (names/paths/wiring) → a repo-specific note, linking to the
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

## PRs
- Never include AI/assistant attribution, session links, or "Generated with …" lines in commit
  messages or PR descriptions.
- Squash to one commit before a PR; check the branch's PR isn't merged
  (`gh pr list --head <branch> --state all --json state`) before committing/pushing.
- Full workflow: `.github/instructions/git-pr.instructions.md`, `.github/skills/pr-squash-sync/`.

## Don't
- No `cd x &&` prefixes in terminal commands — the cwd persists; run plain `git …` (works from
  any subdirectory), never `git -C` for the current repo. Maven: plain `mvn … -pl <module> -am`
  from the repo root, never `cd <module> && mvn`. Same for `npm --prefix`, `ng`, `pytest <pkg dir>`.
- One command per terminal call — avoid `;`/`&&`/`|` chains and `cmd; rm …` tails.
- No heredoc/`sed -i`/`cat > f` file writes — use the editor tools. No inline `python3` heredocs:
  write a script file and run `python3 -I <script>`, or use `jq`.
- No secrets inline in commands (`TOKEN="..."`, `Bearer ...`, raw JWTs) — read from an env var or file.
- Exclude `node_modules` from `find`/`grep`.
- Don't add comments restating what code obviously does.
- Don't add unrequested README/docs files.
- `rm`/`mv`/`cp` are not auto-approved: use `git rm`/`git mv` for tracked files, else `bash .github/skills/guarded-fs/guarded-fs.sh rm|mv|cp …` (cwd-confined).
- Don't suggest `sudo`, `rm -rf`, `curl`/`wget`, or destructive git ops without explicit ask.
- Don't resolve an npm peer-dependency conflict with `--legacy-peer-deps` on a
  security-relevant package (auth, crypto, http-client) — pin a compatible version instead.
