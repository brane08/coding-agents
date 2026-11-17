# COPPER engine 8.1.0 - mock-based unit testing of workflows and infra

Covers: running `Workflow.main()` in plain JUnit with a scripted `ProcessingEngine` proxy (no engine, no DB, no Mockito), `@Transformed` test subclasses, wait/putResponse semantics, `mockConstruction` of engine wiring, JDBC `DataSource` proxies, repository tests. Verified against copper-coreengine 8.1.0 and Mockito 5.24.0. Coverage-profile context (JaCoCo vs ASM instrumenter): `patterns/jacoco-mock-unit-coverage.md`.

## Mock-based unit testing

### Workflow harness (no Mockito needed)
Uninstrumented, `Workflow.wait(...)` only calls `engine.registerCallbacks(wf, mode, millis, String[] cids)` and returns; it does not suspend, so `main()` runs straight through. A scripted engine answers each wait by `putResponse` of the next queued response, then the later `getAndRemoveResponse(cid)` finds it.
```java
@Transformed static class Return extends ReturnWorkflow {}   // see Pitfalls: required marker

void reply(String cid, String v)  { script.computeIfAbsent(cid, k -> new ArrayDeque<>()).add(new Response<>(cid, v, null)); }
void timeout(String cid)          { script.computeIfAbsent(cid, k -> new ArrayDeque<>())
                                          .add(new Response<>(cid, null, null, true, null, null, null)); } // 4th arg = isTimeout

wf.setId("wf-1"); wf.setData(orderId);
wf.setEngine((ProcessingEngine) Proxy.newProxyInstance(cl, new Class<?>[]{ProcessingEngine.class}, (p, m, a) -> {
    if (m.getName().equals("registerCallbacks")) {
        long ms = (Long) a[2];                              // a[0]=wf a[1]=WaitMode a[2]=millis a[3]=String[] cids
        for (String cid : (String[]) a[3]) { waits.add(cid); waitMillis.add(ms);
            Deque<Response<String>> q = script.get(cid); if (q != null && !q.isEmpty()) wf.putResponse(q.poll()); }
    }
    return null; }));
```
- Collaborators injected via setters (`setWorkflowStateService`, `setEventPublisher`): set reflectively via `getClass().getMethod(...)` if the setters live on the subclass, or hand-written `Proxy` / lambda for single-method interfaces (`WorkflowEventPublisher publisher = events::add;`).
- Record step calls in lists (`steps`, `completions` as `"step:STATUS[:OUTCOME]"`, `events`) and assert whole lists: order is the behaviour.
- Assert timeouts via `waitMillis` (`TimeUnit.DAYS.toMillis(14)`), correlation ids via the static `correlationId(id, step)` helper.
- No scripted reply for a cid -> no response put -> `getAndRemoveResponse` returns null -> NPE in workflow: script every wait the path reaches.
- A second scenario in one test needs a fresh harness + fresh workflow instance (`setId` once only).
- `main()` declares `throws Interrupt`; wrap in try/catch -> `AssertionError("unexpected interrupt")` (uninstrumented wait never throws it).
- Branching inputs (fulfillment type, pickup close time) come from the fake state service fields, set per test before `runMain`.

### Wiring classes that `new` their collaborators: `mockConstruction`
For `WorkflowProvider` (constructs `CopperTransactionController`, `PostgreSQLDialect`, `ScottyDBStorage`, `BatchingAuditTrail`, `PersistentScottyEngine`, `PersistentPriorityProcessorPool`, `DefaultProcessorPoolManager`, ...), open a `MockedConstruction` per type around constructor AND call; bundle in an AutoCloseable and close in reverse order.
```java
final MockedConstruction<BatcherBuilder> bb = Mockito.mockConstruction(BatcherBuilder.class,
    (m, c) -> Mockito.when(m.build(any(Integer.class))).thenReturn(Mockito.mock(Batcher.class)));
@SuppressWarnings("rawtypes") MockedConstruction<DefaultProcessorPoolManager> pools = Mockito.mockConstruction(DefaultProcessorPoolManager.class);
try (Mocks m = new Mocks()) {
    new WorkflowProvider(ds, null).start();
    verify(m.engine.constructed().get(0)).startup();
    verify(m.storage.constructed().get(0)).setDialect(m.dialect.constructed().get(0));
}
```
- Verify lifecycle ordering/effects: `start()` starts repo/dialect/stats/audit then engine; `stop()` before `start()` is a no-op (`never()` shutdown); failure in a collaborator `startup()` (`doThrow(...).when(audit).startup()`) is wrapped in `RuntimeException` and engine never starts.
- `DataSource` can be a bare `Mockito.mock(DataSource.class)` when constructors are mocked.

### JDBC without Mockito (repository querying COPPER tables)
`java.lang.reflect.Proxy` for `DataSource` -> `Connection` -> `PreparedStatement` -> `ResultSet` with `switch (m.getName())`; unsupported methods `throw new UnsupportedOperationException(name)` so extra JDBC calls fail loudly. Capture bound params in a field (`setString` -> `boundCorrelation = (String) a[1]`); drive `ResultSet.next()` with a counter field; flip a `failConnection` flag to cover SQLException wrapping.

### Engine fake instead of mock
Subclass `PersistentScottyEngine` overriding only `run`, `notify`, `queryActiveWorkflowInstance`, `queryWorkflowInstances`, `getNumberOfWorkflowInstances`; record args in fields. Simpler than stubbing the big engine surface.

### Workflow repository
`CustomWorkflowRepository(pkgs, classLoader, explicitClasses)` can run for real in a unit test (it instruments via its own class loader): `start()`, `createWorkflowFactory(NAME | className)`, `shutdown()` in `@AfterEach`. Assert the loaded class is `assertNotSame(OrderWorkflow.class, loaded)` (instrumented copy, same name) and `ClassNotFoundException` for unknown names.

## Pitfalls
- `Workflow`'s constructor throws `CopperRuntimeException` unless `getClass().getAnnotation(Transformed.class) != null` (checked in 8.1.0 bytecode). Hence the `@Transformed` subclass; a bare `new OrderWorkflow()` fails.
- `Workflow.setId` throws `IllegalStateException` if the id was already set: one instance per scenario.
- JaCoCo + COPPER's ASM instrumenter: `$jacocoInit` -> `EmptyStackException` when the real engine starts under coverage. Unit tests with the uninstrumented harness above are unaffected; only real-engine `@QuarkusTest` runs need the instrument-artifacts allow-list (see jacoco pattern note).
- Workflow classes appear ~0% under Quarkus coverage; measure them with these harness tests in workflow-core.
- `Response` ctors (8.1.0): `(cid, E, Exception, boolean isTimeout, String, Long, String)` / `(cid, E, Exception)` / `(cid)`. Only the 7-arg form can set `isTimeout`; the 3-arg one is a normal reply.
- Keep `PersistentWorkflow<Long>` data type in harness (`Workflow<Long>`); custom data types are a production constraint (see project CLAUDE.md), not a test one.
