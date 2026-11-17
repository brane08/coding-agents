---
name: mvn-test
description: >
  Use when asked to run tests, verify, or check test results.
  All integration and E2E tests live in mono-quarkus. Unit tests
  for data-hibernate live in data-hibernate.
---
# Maven Test

Run one of:
  bash ~/.copilot/skills/mvn-test/test.sh mono-quarkus                       # all tests
  bash ~/.copilot/skills/mvn-test/test.sh mono-quarkus StudentResourceTest   # specific class
  bash ~/.copilot/skills/mvn-test/test.sh data-hibernate                     # unit tests only

Notes:
- Never pass `-q` to `mvn test` — it suppresses the `Tests run:`/`BUILD SUCCESS`/
  `BUILD FAILURE` summary lines needed for grep-based pass/fail detection (grep can
  return empty on success too, so this makes results ambiguous). Capture the exit code
  immediately after the `mvn` command, not after piping through `tail` — `test.sh`
  already does this correctly via `PIPESTATUS[0]`; use it instead of ad hoc `mvn` calls.
- Quarkus starts once and is shared across all tests in mono-quarkus
- REST responses: {success: true, data: [...]} — assert .body("success", is(true))

Report:
- Pass / fail / error counts
- Names of any FAILED or ERROR tests
- Total time
- On failure: suggested rerun `mvn -pl <module> -am -Dtest=ClassName#method -Dsurefire.failIfNoSpecifiedTests=false test`
