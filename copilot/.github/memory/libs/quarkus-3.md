
## Agroal pool interceptor (Quarkus 3.39)
- Any CDI bean implementing `io.agroal.api.AgroalPoolInterceptor` is auto-registered on the default datasource (`@io.quarkus.agroal.DataSource("name")` qualifier for named). No `@Unremovable` needed.
- `onConnectionAcquire`/`onConnectionReturn` run on the caller thread with the raw JDBC `Connection`, acquire is before JTA enlistment.
- Session-level `set_config(..., false)` on return is unreliable (tx may still be open → reset rolled back → value leaks to next borrower). Set the value on every acquire instead.


## Mock-based unit testing
Covers: testing CDI beans (`@Inject` field injection, `AFTER_SUCCESS` observers, `QuarkusTransaction`) with and without booting Quarkus; unit vs `@QuarkusTest` split. Repo is on Quarkus 3.40.1, Mockito 5.24.0 (poms). Coverage profile: `patterns/jacoco-mock-unit-coverage.md`. Persistence mocks: `hibernate-7.4.md`, `ebean-19.md`; COPPER: `copper-8.1.md`.

### No-boot unit test of an `@Inject` bean (package-private fields)
```java
// bean: @Inject AgentProductQueries productQueries; @Inject ToolContext toolContext;  (package-private, no setters)
groceryTools = new GroceryTools();                 // test in the same package
groceryTools.productQueries = mock(AgentProductQueries.class);
groceryTools.toolContext = new ToolContext();      // real value object when it is a simple holder
```
No `@QuarkusTest`, no `@InjectMocks`; runs in ms and under JaCoCo without the Quarkus agent. Entities can be `mock(Product.class)` or plain `new`.
- Security/role branches: assert WHICH id the dependency got, and that the other path was never taken:
  `when(orderQueries.findByUserId(7L))...; verify(orderQueries, never()).findByUserId(999L)`; `@ParameterizedTest`-style helper (`assertOwnIdUsed(role)`) for customer/driver/unknown/null vs staff/admin.
- Exception swallowing: `when(queries.search("x", 5)).thenThrow(new RuntimeException())` -> assert the user-facing fallback string.

### Observers that must run only after commit (`@Observes(during = AFTER_SUCCESS)`)
Needs a real CDI + JTA container, so this one IS a `@QuarkusTest` with `@InjectMock` on the downstream bean:
```java
@QuarkusTest class OrderPlacedWorkflowStarterTest {
    @Inject Event<OrderPlaced> evt;  @InjectMock CopperGateway gateway;      // io.quarkus.test.InjectMock
    @Test void startsOnlyAfterCommit() throws Exception {
        QuarkusTransaction.requiringNew().call(() -> { evt.fire(e); verify(gateway, never()).start(..); return null; });
        verify(gateway).start(1L, 1L);                       // fired after commit
    }
    @Test void notOnRollback() {
        assertThrows(QuarkusTransactionException.class, () -> QuarkusTransaction.requiringNew().run(() -> {
            evt.fire(e); QuarkusTransaction.setRollbackOnly(); }));
        Mockito.verifyNoInteractions(gateway);
    }
}
```
`@InjectMock` needs `quarkus-junit-mockito` (test scope; present in agent-quarkus/htmx-quarkus) and a normal-scoped bean (`@ApplicationScoped`).
The observer itself (`void onX(@Observes(during=..) E e)`, package-private) can also be called directly in a plain unit test with mocked fields for its catch/else branches (e.g. `CopperException` -> staff notification inside `QuarkusTransaction.requiringNew()`), but then the transaction-phase contract is untested: keep the container test above for that.

### Unit vs @QuarkusTest split
- Mock unit tests: branches, formatting, security decisions, repo query shape. Fast, coverable per module.
- `@QuarkusTest` + real DB (e.g. place-order flow reading/restoring rows via `DataSource` in `@BeforeEach/@AfterEach`): transactions, locking, SQL validity, wiring. Needs a clean/migrated test DB and restoring mutated rows.
- Quarkus coverage inside the app module is a separate (higher) number than module-own unit coverage; do not mix.

## Pitfalls (mock-based)
- `@InjectMock` targets normal-scoped beans only; a `@Singleton`/dependent bean cannot be proxied for mocking, so pick the scope deliberately.
- Plain-unit tests of beans that rely on interceptors (`@Transactional`, `@CacheResult`) skip the interceptor: assert behaviour only, never "runs in a transaction".
- Beans with package-private `@Inject` fields must be tested from the same package (or add setters/constructor injection in a separate change).
- `mvn -f <module>/pom.xml test` skips the root-pom Flyway test-DB reset: only valid when the test schema is already current (see project CLAUDE.md).
