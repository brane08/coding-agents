# AGENTS.md

Tool-agnostic working rules (AGENTS.md format: plain Markdown, closest file wins, the user's chat prompt overrides this file).
Copy to a repo root, or import it from a tool-specific instructions file.

## Output
- Terse: no preamble, no restating the request, no summary unless asked.
- Code blocks complete and copy-paste-ready; no "..." truncation unless huge.
- Skip explanations of well-known concepts unless asked.

## Stack defaults (assume, don't ask)
- Java: Maven multi-module (`mono-quarkus`), Quarkus and Spring Boot, OpenShift target.
- DB: PostgreSQL with Flyway. Frontend: Angular. Python: scope `pytest` to the relevant package dir, not the repo root.
- Shell: zsh on macOS or Ubuntu/Debian; no bash-only syntax unless asked.

## Skills
Skills live in `~/.agents/skills/<name>/` (user) or `<repo>/.agents/skills/<name>/` (project) in the Agent Skills format;
run their scripts as `bash ~/.agents/skills/<name>/<script>` (any of bash, zsh, ksh works). Always write the path with `~`.

| Skill | Use for | Command |
|---|---|---|
| `psql-select` | any read-only SQL (SELECT/EXPLAIN/SHOW/WITH), local Postgres | `select.sh "<sql>"` or `select.sh <db> "<sql>"` |
| `mvn-test` | running Maven tests | `test.sh <module> [TestClass]` (no flags) |
| `mvn-build` | build or package a module | `build.sh <module>` or `build.sh --reactor` |
| `ng-verify` | Angular typecheck and unit tests | `verify.sh <app-dir> --summary` |
| `quarkus-dev` | start `quarkus:dev` in the background | `QUARKUS_PORT=8102 dev.sh` |
| `flyway-check` | migration status (read-only) | `flyway-check.sh [db]` |
| `guarded-fs` | rm/mv/cp confined to the working directory | `guarded-fs.sh rm\|mv\|cp ...` |
| `pr-squash-sync` | sync, squash, push or open a PR | `sync-check.sh <default-branch>` |

Skill logs are written to `<project>/.agents/logs/<skill>.log` (self-ignoring dir). Read them there; `/tmp` is outside the project.

## Commands
- One command per call: no `;`, `&&`, `|` chains and no `cd <dir> &&` prefix (the working directory persists).
  Compound commands defeat command allowlists and prompt.
- Plain `git ...` in the current repo; Maven from the repo root with `-pl <module> -am`; `npm --prefix`, `ng`, `pytest <dir>` take a path.
- `rm`/`mv`/`cp`: `git rm`/`git mv` for tracked files, otherwise `guarded-fs`.
- No secrets inline in commands (`TOKEN=...`, `Bearer ...`, raw JWTs); read them from an env var or file.
- Tests run through `mvn-test` / `ng-verify`. Never pass `-q` to `mvn test`.
- Read-only SQL always through `psql-select`, never plain `psql`. Local DB has no password; never set `PGPASSWORD`; never target a prod host.
- Flyway: `flyway-check` for status. `migrate`, `clean` and `repair` only on local dev databases and only when asked.

## Git and PRs
- Before new work: `sync-check.sh <default>` with a clean working tree. If the branch's PR is already merged (empty tree diff vs
  `origin/<default>`), start a new branch from `origin/<default>`; never merge or rebase the stale one.
- Squash to a single commit before opening a PR (`git merge-base HEAD origin/<default>`, then `git reset --soft <sha>` and recommit).
  A PR has 1-2 commits, 2 only for independent changes that can be reverted separately.
- Attribution in commit messages and PR descriptions is one last line, `by <tool> (<session id>)`, only if the tool exposes a session id.
  No trailers, URLs or "Generated with" lines.
- Force-push only your own branch and only with `--force-with-lease`; never force-push or delete `main`/`master`.

## Auth and role tests
- Prefer REST Assured. Confirm roles per test user with `psql-select` and the endpoint's `@RolesAllowed` / `@PermitAll`; never assume seed ids.

## Model tiers
- Fast: read-only lookups, triage, summaries, pattern-copying boilerplate. Standard: reasoning about why, code-quality and final-branch review.
  Strongest: only for auth, crypto, concurrency or data-migration changes; say so. Each tool tree maps the tiers to its own models.

## Code
- No comments that restate what the code does. No unrequested README or docs files.
- Don't resolve an npm peer-dependency conflict with `--legacy-peer-deps` on a security-relevant package (auth, crypto, http-client); pin a compatible version.
