---
name: mvn-test
description: >
  Use when asked to run tests, verify, or check test results.
  All integration and E2E tests live in mono-quarkus. Unit tests
  for data-hibernate live in data-hibernate.
---
# Maven Test

Run one of:
  bash ~/.claude/skills/mvn-test/test.sh mono-quarkus                       # all tests
  bash ~/.claude/skills/mvn-test/test.sh mono-quarkus CartControllerTest    # specific class
  bash ~/.claude/skills/mvn-test/test.sh data-hibernate                     # unit tests only

Notes:
- Never pass `-q` to `mvn test` — it suppresses the `Tests run:`/`BUILD SUCCESS`/
  `BUILD FAILURE` summary lines needed for grep-based pass/fail detection (grep can
  return empty on success too, so this makes results ambiguous). Capture the exit code
  immediately after the `mvn` command, not after piping through `tail` — `test.sh`
  already does this correctly via `PIPESTATUS[0]`; use it instead of ad hoc `mvn` calls.
- Quarkus starts once and is shared across all tests in mono-quarkus
- Product IDs don't start at 1 — fetch from GET /rest/products dynamically in tests
- REST responses: {success: true, data: [...]} — assert .body("success", is(true))
- WELCOME10 promo must stay active (needed by CheckoutControllerTest)
- DeliveryActionsTest has 2 pre-existing failures — unrelated to app changes

Report:
- Pass / fail / error counts
- Names of any FAILED or ERROR tests
- Total time
