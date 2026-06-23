---
name: mvn-test
description: >
  Use when asked to run tests, verify, or check test results.
  All integration and E2E tests live in htmx-quarkus. Unit tests
  for data-hibernate live in data-hibernate.
---
# Maven Test

Run one of:
  bash ~/.claude/skills/mvn-test/test.sh htmx-quarkus                       # all tests
  bash ~/.claude/skills/mvn-test/test.sh htmx-quarkus CartControllerTest    # specific class
  bash ~/.claude/skills/mvn-test/test.sh data-hibernate                     # unit tests only

Notes:
- Quarkus starts once and is shared across all tests in htmx-quarkus
- Product IDs don't start at 1 — fetch from GET /rest/products dynamically in tests
- REST responses: {success: true, data: [...]} — assert .body("success", is(true))
- WELCOME10 promo must stay active (needed by CheckoutControllerTest)
- DeliveryActionsTest has 2 pre-existing failures — unrelated to app changes

Report:
- Pass / fail / error counts
- Names of any FAILED or ERROR tests
- Total time
