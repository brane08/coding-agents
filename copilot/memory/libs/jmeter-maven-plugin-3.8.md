# JMeter (jmeter-maven-plugin 3.8.0) — run quirks

- Plugin downloads JMeter itself; no local install needed. Plans = `src/test/jmeter/*.jmx`, auto-globbed by `-Pjmeter`.
- Phases: `configure` (generate-resources) → `jmeter` (integration-test) → `results` (verify). Build fails on any failed
  sample (0% error threshold).
- `-DskipTests` also skips the jmeter phase. To skip only surefire: `-Dtest=NoSuchTest -Dsurefire.failIfNoSpecifiedTests=false`.
- Running `verify` reaches surefire first; if unit tests need a freshly reset test DB, they fail and JMeter never runs.
- JMeter marks every HTTP 4xx sample `success=false`. A ResponseAssertion on the code with `Assertion.assume_success=false`
  does NOT rescue it; negative-path samplers (expect 403/404) need `assume_success=true` ("Ignore Status").
  Verified: flipping it on the 6 negative 403/404 assertions took the run from 30/171 errors to 0/171.
- Re-running with old `target/jmeter/reports` present fails ("folder is not empty"); use `clean verify` (or delete
  `target/jmeter/{reports,results}` first).
- CSV results (`target/jmeter/results/*.csv`) are the source of truth: last column = success. Subagent summaries of
  a run were wrong once ("0 errors" for plans whose CSV showed `false`) — check the CSV.
- Signed-cookie plans: preprocessor HMAC-SHA256 over the id string with the app's cookie secret; the id must exist in the
  DB the app is actually running against, with the role the sampler assumes (wrong id → anonymous → 403 for the wrong reason).
- Before handing a run to a subagent, smoke each negative-path request yourself with httpie
  (`uvx --from httpie http --ignore-stdin --print=h GET <url> "Cookie:GROCERY_USER=<id>.<sig>"`), with a positive control per
  role. 401 everywhere = cookie signing/secret wrong (read the secret from application.yml at runtime, don't inline it).
- Check port with `lsof -nP -iTCP:<port> -sTCP:LISTEN` (curl is not allowed in this setup).
