# Hibernate 7.4 / JPA (jakarta.persistence) - mock-based repository unit tests

Covers: unit-testing `EntityManager`-based repositories with Mockito only (no DB, no Quarkus): fluent `Query`/`TypedQuery` mocks, SQL/JPQL verification, native `Object[]` rows, locking, `@Transactional` bypass. Repo uses Hibernate 7.4.11.Final, Mockito 5.24.0, JUnit 5. Profile/fan-out context: `patterns/jacoco-mock-unit-coverage.md`.

## Mock-based unit testing

Repos here take `EntityManager` in the constructor and use only `jakarta.persistence` API (no Criteria, Tuple, Session, unwrap), so there is nothing Hibernate-specific to mock. `@Transactional` (jakarta.transaction) is an interceptor binding: with plain `new Repo(em)` it is inert, no bypass needed. Entities carry `org.hibernate.annotations` -> hibernate-core must be on the test classpath, but entities are plain `new X()` POJOs.

### Base setup (one per test class)
```java
@SuppressWarnings({"unchecked", "rawtypes"})
@ExtendWith(MockitoExtension.class)
class FooRepositoryCoverageTest {
    @Mock EntityManager em;
    @Mock(answer = Answers.RETURNS_SELF) TypedQuery<Product> productQuery; // setParameter/setMaxResults/... return itself
    @Mock(answer = Answers.RETURNS_SELF) Query untypedQuery;               // count / executeUpdate
    @Mock(answer = Answers.RETURNS_SELF) Query nativeQuery;
    FooRepository repo;

    @BeforeEach void setUp() {
        repo = new FooRepository(em);
        lenient().when(em.createQuery(anyString(), eq(Product.class))).thenReturn(productQuery);
        lenient().when(em.createQuery(anyString())).thenReturn(untypedQuery);
        lenient().when(em.createNativeQuery(anyString())).thenReturn(nativeQuery);
        lenient().when(productQuery.getResultList()).thenReturn(List.of());
        lenient().when(productQuery.getResultStream()).thenAnswer(i -> Stream.empty()); // streams are single-use
        lenient().when(untypedQuery.getSingleResult()).thenReturn(0L);
        lenient().when(untypedQuery.executeUpdate()).thenReturn(0);
        lenient().when(nativeQuery.getResultList()).thenReturn(List.of());
    }
}
```
Without `RETURNS_SELF` stub every chain step: `when(q.setParameter(anyString(), any())).thenReturn(q)`.

### Verify query text, bindings, paging, absent-branch
```java
verify(em).createQuery(argThat((String q) -> q.contains("deleted = false")), eq(Product.class));
verify(productQuery).setParameter("c", "Dairy");
verify(productQuery).setFirstResult(20);  verify(productQuery).setMaxResults(10);   // page 3 x size 10
verify(orderQuery, never()).setParameter(eq("s"), any());                            // null filter skips binding
verify(em, never()).createQuery(anyString(), eq(Product.class));                     // empty-id short-circuit
```
`argThat((String q) -> ...)` needs the explicit lambda param type: `createQuery` is overloaded (String / String,Class / CriteriaQuery) and plain `argThat(q -> ...)` is ambiguous.

### Optional via getResultStream
```java
when(productQuery.getResultStream()).thenReturn(Stream.of(p));   // present
// default stub (Stream.empty()) covers absent
```

### Routing many native queries by SQL fragment (several `createNativeQuery` calls in one method)
```java
final Map<String, Query> routes = new LinkedHashMap<>();
lenient().when(em.createNativeQuery(anyString())).thenAnswer(inv -> route(inv.getArgument(0)));
Query nq(String fragment) { Query q = mock(Query.class);
    lenient().when(q.setParameter(anyString(), any())).thenReturn(q); routes.put(fragment, q); return q; }
Query route(String sql) { return routes.entrySet().stream().filter(e -> sql.contains(e.getKey()))
    .map(Map.Entry::getValue).findFirst().orElseThrow(() -> new AssertionError("unstubbed native SQL: " + sql)); }
```
Unstubbed SQL fails loudly (catches accidental extra queries). Alternative for a single call site: `when(em.createNativeQuery(contains("FROM delivery_slots ds"))).thenReturn(slotQuery)`.

### Native result rows (`Object[]`, scalars)
- `getResultList()` for multi-column native SQL: `List.of(new Object[]{7L, LocalDate.of(...)}, ...)`; single column: `List.of(3L, 1L)`; single row: `getSingleResult()` -> `new Object[]{10, 0}`.
- Drivers return varying types; repo converters usually accept several. Feed every variant the code handles: `LocalDate`, `java.sql.Date`, `String` date, `Long`/`Integer`/`BigDecimal`/`String` numbers, and `null` (-> zero/default). That is where the branches are.
- No row: `thenThrow(new NoResultException())` for `getSingleResult()`.
- Mixed Object[] list generics: `List.<Object[]>of(row1)`; consecutive calls: `thenReturn(first, second)`.

### Locking, persist, update counts
```java
when(em.find(Product.class, 7L, LockModeType.PESSIMISTIC_WRITE)).thenReturn(p);   // verify lock mode by stubbing it; wrong mode -> null -> NPE/not-found path
ArgumentCaptor<Object> captor = ArgumentCaptor.forClass(Object.class);
verify(em, atLeastOnce()).persist(captor.capture());                              // then filter captor.getAllValues() by instanceof
when(untypedQuery.executeUpdate()).thenReturn(1);                                  // 0 = CAS lost / row missing branch
InOrder io = inOrder(del, prune); io.verify(del).executeUpdate(); io.verify(prune).executeUpdate();  // statement ordering
```
Money: compare with `compareTo` (`assertMoney(expected, actual)`), not `equals` (scale).

### Collaborators
Mock sibling repos (`SystemConfigRepository`, `BranchStockRepository`, ...) and stub config values leniently in setUp; assert on the exact args they received, not just results.

## Pitfalls
- MockitoExtension is strict: unused stubs fail with `UnnecessaryStubbingException`. Shared setUp stubs must be `lenient()`; per-test stubs plain `when`.
- `anyString()`/`any()` do not match differently-typed overloads; `setParameter("p", x)` with `anyString(), any()` ok, positional `setParameter(1, x)` needs `anyInt()`.
- `thenReturn(Stream.of(..))` reused across calls returns an already-consumed stream: use `thenAnswer(i -> Stream.of(..))` when the method may be called twice.
- Mock-only tests prove query shape and branching, not that the JPQL/native SQL is valid; invalid SQL still needs a real-DB test.
- Parity: data-ebean mirrors each repo; write the same case list for both (see `ebean-19.md` "Mock-based unit testing").
- `@QuarkusTest` coverage of the same classes is a separate, higher number; do not mix with module-own unit coverage.
