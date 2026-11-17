---
applyTo: "**/*Test*.java,**/*IT*.java"
---
# Tests, auth/role
- Auth/role tests: REST Assured first (`@QuarkusTest`), pattern in `~/.copilot/memory/patterns/rest-assured-csv-role-matrix.md`.
- Confirm roles per test user via `bash ~/.copilot/skills/psql-select/select.sh` and the endpoint's `@RolesAllowed`/`@PermitAll`. Never assume seed ids.
- Matrix shape: one `@ParameterizedTest` + `@CsvFileSource`, columns `name,role,method,path,query,expectedStatus,bodyRegex`; a missing or empty CSV must fail.
- Assert both directions: allowed → 2xx, disallowed → 403, no/invalid token → 401 (`ANON` = invalid token, not a missing header).
- Run: `bash ~/.copilot/skills/mvn-test/test.sh <module> [TestClass]`. Single rerun: `mvn -pl <module> -am -Dtest=Class#method -Dsurefire.failIfNoSpecifiedTests=false test`.
- Never `-q` on `mvn test`. REST responses are `{success, data}`.
- JMeter only for load/perf or smoke against a deployed env.
