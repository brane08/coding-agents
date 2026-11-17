# JaCoCo + mock-based unit coverage (multi-module Maven, Quarkus/Java)

Covers: opt-in coverage profile, what to exclude, JaCoCo vs bytecode-instrumenting libs, mock recipes for repo/workflow code, fanning test-writing out to subagents.

## Profile
- Opt-in `coverage` profile in the root pom (default build unchanged): `mvn test -Pcoverage`. Reports at `<module>/target/site/jacoco/`.
- Submodule surefire `argLine` must start with `@{argLine}` (root defines it empty) or the agent is silently dropped.
- Excludes (no value, inflate the denominator): DTO/entity/bean packages, generated `*MapperImpl*` (MapStruct), `*Producers*` (CDI wiring), `*Exception`, declarative workflow-definition packages (unless unit-tested).
- Measure the unit-test figure per module on its own tests. `@QuarkusTest` coverage inside the app module is a separate (higher) number; don't mix them.
- Ratchet: add jacoco `check` (line COVEREDRATIO >= 0.80, per BUNDLE) to the profile only after every module passes.

## Instrumenting libs break under JaCoCo
- Libraries that rewrite bytecode with ASM (COPPER) crash on `$jacocoInit`: `EmptyStackException` in `BuildStackInfoAdapter`, engine fails to start, tests 500.
- `quarkus.jacoco.includes/excludes` only filter the REPORT. Fix = allow-list instrumented artifacts with `quarkus.jacoco.instrument-artifacts.<key>.group-id/artifact-id` (surefire systemPropertyVariables), leaving the workflow module off.

## Mock recipes
- Repositories: mock `EntityManager`/`Query` (JPA) or `Database`/`SqlQuery`/`Query` (Ebean); assert built SQL/JPQL + parameter binding + null/empty branches. Mock-only tests only reach ~70-90%; native SQL correctness still needs a real DB.
- Classes that build collaborators with `new` in the constructor/start method: Mockito `mockConstruction(X.class, ...)` for each (needs Mockito 5 / inline mock maker); open the scope around both constructor and call, no refactor needed. Add `mockito-core` test dep if the module lacks it.
- Agent tool classes with `@Inject` fields: plain `new` + set package-private fields + Mockito mocks; no Quarkus boot. Test security branches by asserting WHICH id/role the dependency was called with.
- Assert on exact args (`verify(..).findByUserId(id)` + `never()` on the wrong one), not just return values.
- Unit tests that read jsonb back may lose BigDecimal scale (`"3.5"` vs `"3.50"`): normalise with `setScale` at the consumer.
- Real-DB tests against a long-lived dev DB fail with `column ... does not exist` when migrations are pending; check `flyway:info` before blaming code.

## Dual-backend repos (JPA + Ebean) - recipes distilled
- Run: `mvn test -Pcoverage` (root); single class: `mvn -pl <module> test -Dtest=XTest`. Rebuild siblings first (`mvn clean install -DskipTests`) when `-f <module>/pom.xml` shows "cannot find symbol".
- Keep both backends' tests in parity: same test names/cases per repo (`XRepositoryTest` / `XRepositoryCoverageTest` in each module); a fix or new branch in one repo => mirrored test in the other, same change.
- JPA: `em.createNativeQuery(startsWith("INSERT INTO t"))` / `contains("FROM x")` -> per-query mock; every `setParameter(anyString(), any())` stub returns the SAME mock (`lenient()` in setUp) or the fluent chain NPEs.
- JPA typed-null binding: code does `q.unwrap(org.hibernate.query.NativeQuery.class).setParameter("b", (Long) null, Long.class)`. Mock `q.unwrap(NativeQuery.class)` to return a `NativeQuery<?>` mock, whose `setParameter` returns itself; verify the typed call.
- Ebean: `doReturn(x).when(mock).method()` for all generic fluent steps; `db.sqlUpdate(..)` -> `SqlUpdate` mock returning itself; null binds use `setNull("b", Types.BIGINT)` -> `verify(upd).setNull(..)` and `verify(upd, never()).setNull(anyString(), anyInt())` for the non-null path; `SqlRow` mocks with `getLong/getString/getInteger` per column alias.
- Ebean transactions: `doReturn(tx).when(db).beginTransaction()`; code uses try-with-resources, so `verify(tx).commit()` and, on exception paths, `verify(tx, never()).commit()` (close() is implicit, `verify(tx).close()` works).
- Match SQL by fragment (`startsWith`/`contains`), unstubbed SQL returns null -> NPE that points at the changed statement.

## Pitfalls found
- Mockito strict stubs: shared setUp stubs `lenient()`; per-test stubs plain; unused stubs throw `UnnecessaryStubbingException`.
- `@Transactional` is NOT applied to instances built via producers/`new` (interceptors only wrap CDI beans), so tx behaviour can't be asserted in unit tests, and a missing annotation is invisible to them. Cover it in a `@QuarkusTest`/real-DB test. (Ebean enhanced `@Transactional` classes also break under mockDb; see `libs/ebean-19.md`.)
- Ebean `db.sqlQuery` needs explicit column aliases (`AS name`); mock `SqlRow.getX("alias")` must use the alias, not the table column. JPA native rows are `Object[]` by position.
- `startsWith(...)` SQL matchers break silently when someone changes the SQL prefix/whitespace (stub misses -> null mock -> NPE). Prefer `contains` on a distinctive fragment for statements likely to be reformatted.
- Mock tests can't prove real SQL validity, constraint/enum casts, locking, or atomicity (e.g. batch allocate/restore, double-submit). Those belong in htmx-quarkus real-DB tests (test DB reset by the root pom); unit tests only pin the call shape.

## Baseline caveat
- A recorded baseline goes stale quickly after test waves. Example: repo baseline note said hibernate 44.1/42.2, ebean 54.0/50.0, htmx-quarkus 76.0/61.0 (line/branch %), while later runs measured 90.1/81.5, 90.2/80.1 and 88.8/71.7. Always re-measure (`mvn test -Pcoverage -Dmaven.test.failure.ignore=true`) before quoting or planning from a baseline file.

## Fan-out to subagents (worked: ~8 agents, one wave per gap list)
- Generate the gap list first (classes under 80% with >=10 missed lines) from `jacoco.csv`.
- One agent per class group; haiku for plain repos/value classes, sonnet for infra (workflow engines, construction mocking).
- Brief: mock-based tests only; NEW `*CoverageTest` files; no `src/main` edits; verify with `mvn -pl <module> test -Dtest=<Class> -Dsurefire.failIfNoSpecifiedTests=false`; retry after 30s on build errors from sibling agents' files; report suspected prod bugs, never fix them.
- Agents surface real bugs (NULL->"null" string concat, integer division before round, `split("=")` on values, check-then-write races, ORM parity gaps). Log them in the todo; fix separately with RED->GREEN tests in both persistence backends.
- Re-measure after each wave with one `mvn test -Pcoverage -Dmaven.test.failure.ignore=true -pl <modules>`.


## Library notes
- `libs/hibernate-7.4.md` - EntityManager/Query/TypedQuery mocks (RETURNS_SELF, native Object[] rows, SQL-fragment routing, locks).
- `libs/ebean-19.md` ("Mock-based unit testing") - Database/Query/ExpressionList/SqlQuery/SqlRow/Transaction mocks via doReturn, Junction RETURNS_SELF.
- `libs/copper-8.1.md` - scripted ProcessingEngine proxy + @Transformed subclasses, mockConstruction of engine wiring, JDBC proxies.
- `libs/quarkus-3.md` ("Mock-based unit testing") - no-boot @Inject field tests, AFTER_SUCCESS observer test with @InjectMock, unit vs @QuarkusTest split.
