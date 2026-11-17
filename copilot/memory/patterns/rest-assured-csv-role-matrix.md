# REST Assured CSV role matrix (vs JMeter)

## When to use which
- **REST Assured `@QuarkusTest`** — functional smoke: role × endpoint × status matrices, guard checks (200/401/403/404). Runs in `mvn test`/CI, no live server, per-case names in the surefire report.
- **JMeter** — only load/perf plans and smoke against a *deployed* env. Functional matrices in JMeter need a live server, a generated jmx, `-DskipTests` silently skips the plugin, and failures are judged from result CSVs.

## Shape
- One `@ParameterizedTest(name = "{0}") @CsvFileSource(files = "src/test/resources/api-matrix.csv", numLinesToSkip = 1)`.
- Columns: `name,role,method,path,query,expectedStatus,bodyRegex` (no commas in fields). Coverage grows by adding rows, not code.
- `token(role)` switch over the project's JWT/cookie test helper; `ANON` sends an **invalid** token (a missing header can return 200 on whoami-style endpoints).
- Assert `statusCode(expected)`; apply `bodyRegex` (`(?s)` prefix) only when non-empty — 401/403/404 bodies are empty, `.*` fails on empty.
- A zero-row or missing CSV must fail, not skip.

## Rules for rows
- Before any 403 row: confirm the test user's roles in the DB (`select.sh`) and the endpoint's `@RolesAllowed`/`isPresent()` guard in code. Never assume seed ids; look them up.
- Assert both directions: allowed → 2xx, disallowed → 403, no/invalid token → 401.
- Guardian/owner-scoped reads: one row for the owned id (200), one for another owner's id (403).
- Missing required params may return 200, not 400 — verify before adding a row.

## Why one smoke row per GET endpoint
Finds stale query names that compile fine: a native SQL column rename → 500, JPQL on a removed field → 400 when the app maps `IllegalArgumentException` to 400. Subagent scans for these were unreliable; run the rows.

## Pitfalls
- Tests are non-hermetic if they hit a live DB + seed ids (same as the rest of the suite) — note it; Testcontainers is the later fix.
- Workflow/engine POSTs return 503 when the engine is disabled in test profile — leave out, test the DB row via an injected service.

## Applying to another project (e.g. grocery shop)
Swap `token(role)` for that app's auth (cookie session → `.cookie(...)`), roles customer/staff/admin/driver, seed ids from its own DB; keep CSV columns and test class identical.
