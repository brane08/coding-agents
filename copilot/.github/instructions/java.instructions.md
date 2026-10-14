---
applyTo: "**/*.java,**/pom.xml"
---
# Java / Maven / Quarkus
- Maven multi-module (`mono-quarkus`); Quarkus + Spring Boot mix; OpenShift target.
- Run Maven from the repo root: `mvn … -pl <module> -am`. Never `cd <module> && mvn`; `-f <abs>/pom.xml` only for a project outside cwd.
- Never pass `-q` to `mvn test` (hides the `Tests run:`/`BUILD` summary lines).
- Prefer `.github/skills/mvn-build/build.sh <module>` and `.github/skills/mvn-test/test.sh <module> [TestClass]`.
- After changes to `data-ebean` or `workflow-core`, `mvn install -DskipTests -pl <module> -am` so dependents pick up new jars (stale jars → `NoSuchMethodError`); `build.sh --reactor` only packages.
- Flyway: `flyway:info` is fine; never `flyway:clean`, `flyway:repair` or `flyway:migrate` without an explicit ask.
- Third-party jar API with no source/docs: check `.github/memory/libs/` first, then `javap -p [-c] -cp <jar> <Class>` (no extraction).
- Dependency questions: `mvn dependency:tree -pl <module>`; do not edit `pom.xml` to resolve conflicts without asking.
- Entity wiring chain: DTO (core-api) → Entity/Mapper/ServiceImpl (data-ebean|data-hibernate) → Resource + producers (mono-quarkus) → `*ResourceTest`.
- Design patterns: `.github/memory/patterns/` (e.g. `boundary-control-layering`, `workflow-mybatis-layer`, `workflow-async-events`).
