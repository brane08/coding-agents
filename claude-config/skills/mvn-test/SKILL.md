---
name: mvn-test
description: >
  Use when asked to run tests, verify, or check test results.
  All integration and E2E tests live in mono-quarkus. Unit tests
  for data-hibernate live in data-hibernate.
---
# Maven Test

**Dispatch, don't run inline.** Hand the chosen command below to the `quick-triage`
agent (pinned to haiku; no `model:` override) and have it return the Report section.
If anything failed, follow up with `test-aggregator` for the `-Dtest=` rerun commands.
The only inline exception is a single-class `-Dtest=` rerun right after a fix.

Run one of:
  bash ~/.claude/skills/mvn-test/test.sh mono-quarkus                       # all tests
  bash ~/.claude/skills/mvn-test/test.sh mono-quarkus StudentResourceTest   # specific class
  bash ~/.claude/skills/mvn-test/test.sh data-hibernate                     # data-hibernate (+ upstream modules) tests

Notes:
- Never pass `-q` to `mvn test` — it suppresses the `Tests run:`/`BUILD SUCCESS`/
  `BUILD FAILURE` summary lines needed for grep-based pass/fail detection (grep can
  return empty on success too, so this makes results ambiguous). Capture the exit code
  immediately after the `mvn` command, not after piping through `tail` — `test.sh`
  already does this correctly via `PIPESTATUS[0]`; use it instead of ad hoc `mvn` calls.
- Quarkus starts once and is shared across all tests in mono-quarkus

Report:
- Pass / fail / error counts
- Names of any FAILED or ERROR tests
- Total time
