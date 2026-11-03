# Global memory index

Open only the note that matches the task; each note's first lines say what it covers.

## rules/ (detail moved out of CLAUDE.md)
`hooks-and-guards` (what is denied/prompted and why) · `config-sync` (repo ↔ ~/.claude) ·
`session-scans` (delegation/permission/context audits) · `git-prs` (squash, attribution, PR checks)

## libs/
`keepassjava2-2.2.4` (KeePass API, JPMS split-package) · `esbuild-esm` (exported `let`
read-only, TS2540) · `javafx-21` (FXML/dialog/timer quirks, module-info opens) ·
`javafx-21-fat-jar-packaging` (shade, launcher wrapper, macOS .app, CI release) ·
`fxtrayicon-4.2.3` · `testfx-4.0.18-monocle` (headless JavaFX UI tests) · `jnativehook-2.2.2` ·
`copper-8.1` (mock-based workflow tests, workflow constraints, wait/notify recipe) ·
`hibernate-7.4` (mock-based repo unit tests) · `ebean-19` · `quarkus-3` (Agroal pool interceptor,
@Unremovable, legacy-jar) · `shedlock` (@SchedulerLock rules) · `jmeter-maven-plugin-3.8` (run
quirks) · `spring-cloud-gateway-server-webmvc-5.0.3` · `claude-code-permissions` (prompts,
additionalDirectories, allow-rule matching, hooks, subagent tool gaps)

## patterns/
`tracking-pattern` (findings/items/decisions/reviews folder; DS/FE/BG/TS/DC/RV-nnn IDs; states
DOING·BLOCKED·PARTIAL·PENDING·BACKLOG·DEFERRED·DONE·WONT-DO; dated items; archive at 30 DONE) ·
`self-contained-data-module` (ORM-swappable data modules) · `workflow-mybatis-layer` (plain
mybatis, CDI SqlSessionFactory) · `workflow-async-events` (WorkflowOutcomeEvent, fireAsync) ·
`deterministic-agent-platform` (stub+gate, verify artifacts) · `declarative-ai-agent-quarkus`
(LangChain4j agent service) · `boundary-control-layering` (per-feature web-layer split) ·
`quarkus-postgres-schema-multitenancy` (schema-per-tenant) · `rest-assured-csv-role-matrix`
(role×endpoint×status smoke; authorisation-test rules) · `jmeter-load-smoke` (pre-flight checks
before any JMeter run) · `jacoco-mock-unit-coverage` (JaCoCo with mock-based unit tests,
multi-module Maven) · `claude-config-repo-sync` (repo ↔ ~/.claude merge routine, dir rename) ·
`money-multi-country-postgres` · `pre-prod-schema-folding` · `cloud-agent-session-bootstrap` ·
`framework-neutral-web-core` · `open-source-release-audit` · `agent-context-cost`
