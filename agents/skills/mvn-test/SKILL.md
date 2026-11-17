---
name: mvn-test
description: Run Maven tests for a module or a single test class and report pass/fail/error counts, failing test names and duration. Use when asked to run tests, verify, or check test results. All integration and E2E tests live in mono-quarkus; unit tests for data-hibernate live in data-hibernate.
compatibility: Requires bash and Maven (mvn) on PATH.
metadata:
  version: "1.0"
---
# Maven Test

Run one of:

```
bash ~/.agents/skills/mvn-test/test.sh mono-quarkus                       # all tests
bash ~/.agents/skills/mvn-test/test.sh mono-quarkus StudentResourceTest   # specific class
bash ~/.agents/skills/mvn-test/test.sh data-hibernate                     # data-hibernate (+ upstream modules)
```

The script takes only `[<module> [TestClass]]`; flags are rejected. If your tool supports cheap sub-agents,
delegate the run and the failure summary to one instead of running tests in the main conversation.

Notes:
- Never pass `-q` to `mvn test`: it suppresses the `Tests run:` / `BUILD SUCCESS` / `BUILD FAILURE` summary lines that
  pass/fail detection needs. Capture the exit code right after the `mvn` command, not after piping through `tail`;
  `test.sh` does this already via `PIPESTATUS[0]`, so use it instead of ad hoc `mvn` calls.
- Quarkus starts once and is shared across all tests in mono-quarkus.
- The full output is in `<project>/.agents/logs/mvn-test.log` (self-ignoring dir); read it there, not from `/tmp`.

Report:
- Pass / fail / error counts
- Names of any FAILED or ERROR tests
- Total time
