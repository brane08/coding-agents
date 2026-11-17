# Ebean 19.4.0

- **Scalar RETURNING:** `db.sqlQuery(...).mapToScalar(Long.class).findOne()` —
  `findSingleAttributeList` does NOT exist on `SqlQuery`.
- `BeanPersistAdapter`, `@DbJson` behavior carried over unchanged from 17.x — no
  breaking API changes observed between 17 and 19 for these two.

## Unit-testing a class with `@Transactional` methods (enhancer clinit gotcha)
Ebean's build-time enhancer injects a static `_$initProfileLocations()` into any class with
`@Transactional`-annotated methods, called from `<clinit>`. It calls
`ProfileLocation.create(...)` which NPEs (`XBootstrapService.profileLocationFactory()` returns
null) unless a real `Database`/`EbeanServer` has already bootstrapped in that JVM. A Mockito unit
test that merely does `new SomeEnhancedServiceImpl(mockDb)` — never touching a real `Database` —
triggers this on first class load and fails, even standalone (not just under `-Dtest` filters).
Workaround: don't unit-test `@Transactional` Ebean service classes directly with a mocked
`Database` in a module with no real Ebean bootstrap in its test suite (e.g. `data-ebean` here,
which isn't wired into any runtime `@QuarkusTest`). Test the ORM-agnostic logic via the mirror
implementation in a module that IS bootstrapped, or `@Disabled` with an explanatory reason.


## Mock-based unit testing
Covers: Mockito-only unit tests for `Database`-based repos (no DB, no bootstrap): fluent `Query`/`ExpressionList` chains, `SqlQuery`/`SqlRow`/`SqlUpdate`, `Transaction`, update queries, Junctions. Verified against ebean 19.6.0 + Mockito 5.24.0. Profile/fan-out: `patterns/jacoco-mock-unit-coverage.md`. JPA twin: `hibernate-7.4.md`.

data-ebean repos take `Database` via constructor and open transactions with `db.beginTransaction()` (no `@Transactional` in main), so `new Repo(mockDb)` works; the enhancer clinit gotcha above does not apply. Entities are enhanced classes but plain `new X()` works.

### Use `doReturn(..).when(..)`, not `when(..).thenReturn(..)`
Generic fluent returns (`ExpressionList<T>` vs `Query<T>`, varargs/overloads) make `when().thenReturn()` fail to compile or hit the wrong overload. Pattern for every chain step, all `lenient()` in setUp:
```java
@Mock Database db; @Mock Query<Order> q; @Mock ExpressionList<Order> expr; @Mock Transaction tx;
@BeforeEach void setUp() {
    repo = new OrdersRepository(db, ...);
    lenient().doReturn(q).when(db).find(Order.class);
    lenient().doReturn(expr).when(q).where();
    lenient().doReturn(expr).when(expr).eq(anyString(), any(Object.class));   // also ne/in/orderBy/setMaxRows/setFirstRow
    lenient().doReturn(expr).when(expr).in(anyString(), any(List.class));      // Collection overload
    lenient().doReturn(List.of()).when(expr).findList();
    lenient().doReturn(0).when(expr).findCount();
    lenient().doReturn(q).when(expr).forUpdate();      // ExpressionList.forUpdate() returns the Query; then stub q.findOne()
    lenient().doReturn(tx).when(db).beginTransaction();
}
```
- varargs `in("f", a, b)`: stub with `any(Object[].class)`, verify with the literal values `verify(expr).in("fulfillmentType", "pickup", "curbside")`.
- Update queries: `db.update(Order.class)` -> `UpdateQuery<Order>`; `.set(anyString(), any())`, `.where()` -> ExpressionList, terminal `.update()` returns int (`doReturn(3).when(expr).update()`).
- OR groups: `Junction<T> j = mock(Junction.class, RETURNS_SELF); doReturn(j).when(expr).or(); doReturn(rows).when(j).findList();` then capture bounds `verify(j).le(eq("validFrom"), fromCaptor.capture())`.
- `exists()`, `findOneOrEmpty()` (`Optional`), `findOne()` (null = absent) all stubbed the same way.
- `db.find(Entity.class, id)` (by-id overload) is a different method from `db.find(Entity.class)`: stub both when code uses both.

### Raw SQL: SqlQuery / SqlRow / SqlUpdate
```java
lenient().doReturn(sqlQuery).when(db).sqlQuery(anyString());
lenient().doReturn(sqlQuery).when(sqlQuery).setParameter(anyString(), any());
doReturn(List.of(row)).when(sqlQuery).findList();        // multi-row;  doReturn(row).when(sqlQuery).findOne(); // single (null = none)
doReturn(9L).when(row).getLong(anyString());  doReturn("x").when(row).getString("name");
doReturn(new BigDecimal("42.50")).when(row).getBigDecimal("revenue");
doReturn(java.sql.Date.valueOf("2026-10-01")).when(row).getDate("order_date");
doReturn(Timestamp.from(t)).when(row).getTimestamp("created_at");   // null Timestamp -> null-Instant branch
doReturn(1).when(sqlUpdate).execute();                              // rows affected; 0 = lost-race branch
verify(db).sqlQuery(contains("b.city = :city"));  verify(sqlQuery).setParameter("city", "Dublin");
verify(db, never()).sqlQuery(contains("out_for_delivery"));          // branch skipped
verify(db).sqlUpdate(startsWith("delete from grocery.household_members"));
```
- Sequential results from one stub: `doReturn(null, row).when(query).findOne();` (exists-check then insert-returning).
- Using `anyString()` row stubs (`getLong(anyString())` -> same value for all columns) is a quick way to cover a mapper; use named stubs when asserting field mapping.
- Rows with `null` columns: `doReturn(null).when(row).getLong("total")` covers boxed-null defaults.
- Create extra `mock(SqlRow.class)` inside the test for multi-row lists (housemate names etc.).

### Transactions
```java
verify(tx).commit();  verify(tx).close();                 // happy path
verify(tx, never()).commit(); verify(tx).close();         // validation/rejection/no-op path must still close
verify(db, never()).beginTransaction();                   // failed pre-validation (e.g. missing config) before tx
ArgumentCaptor<Object> saved = ArgumentCaptor.forClass(Object.class);
verify(db, times(2)).save(saved.capture());               // order of saved entities = saved.getAllValues()
```
`db.save(..)` / `db.update(..)` on entities are void-ish mocks: capture and assert field values.

### Config / exception branches
Stub collaborator `configRepo.getValue("vat_rate")` to `null`/`"free"` to hit `IllegalStateException` branches (assert message contains the key and that `beginTransaction` never ran).

## Pitfalls (mock-based)
- `when(expr.eq(...))` style breaks on generic/overload resolution; use `doReturn` everywhere.
- Strict stubs: setUp stubs `lenient()`, per-test overrides plain `doReturn` (re-stubbing the same call in the test is fine).
- `findCount()` is `int` in this API, `update()`/`execute()` return `int`: `doReturn(4L)` there throws `WrongTypeOfReturnValue`.
- Real Ebean tests (`DB.*`, `Database` bootstrap) are not needed or used here; static `DB.xxx` calls in a class under test cannot be mocked without `mockStatic` and break the module's no-bootstrap rule - inject `Database`.
- Mock tests do not prove generated SQL/ORM expression correctness (property vs column names, `:param` binding in the real parser); keep a real-DB/`@QuarkusTest` path for that.
- Keep case lists identical to the data-hibernate twin; behaviour fixes must land in both backends.
