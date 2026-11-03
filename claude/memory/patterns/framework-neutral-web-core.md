# Framework-neutral web core (porting a Quarkus web app to Spring Boot)

Covers: module layout and seams for sharing templates, control services and view models between a Quarkus app and a Spring Boot app while keeping the Quarkus app green. Source: two port analyses (HTMX+Qute app and Angular/JAX-RS backend); nothing was built, counts were from greps.

## Decisions
- Extract a shared framework-neutral module; write the controllers/resources twice as thin adapters (Spring MVC + Spring Security + `TransactionTemplate`). No in-place conversion; Jersey-on-Spring (to share JAX-RS) and Thymeleaf were rejected.
- Keep the Quarkus app green through the extraction. Port tests last.
- Server-rendered app: standalone Qute (`qute-core`) in Spring so templates/HTMX markup are shared unchanged; re-register all globals and extensions. Spike first (globals, extensions, layout includes).
- Hibernate only on Spring (no Ebean: its JTA internals are pinned to the Ebean version).

## Layout
```
core-api, workflow-core, data-hibernate   already neutral
web-common    templates, static assets, control services, view models, plain tests
app-quarkus   old app reduced to glue
app-spring    Boot main, @Configuration repo beans, auth, tx, scheduling, workflow wiring
```
- `web-common` keeps `jakarta.inject`/`jakarta.enterprise` as provided deps. Spring ignores CDI scopes: each bean needs `@Component` or an `@Bean` registration in the Spring app.
- Classes with only plain/CDI-annotation imports in `*/control/*`, rate limiters, hashers, `CurrentUser` move with no change; confirm no plain class imports a coupled one.

## Seams needed before moving a class
| Quarkus piece | Seam |
|---|---|
| `QuarkusTransaction` | interface over `TransactionTemplate` / `REQUIRES_NEW` |
| CDI `Event` / `@Observes(TransactionPhase)` | `@TransactionalEventListener(AFTER_COMMIT)` / `TransactionSynchronization` (semantics differ; after-commit workflow start must be re-implemented) |
| Quarkus Mailer, `@ConfigProperty` | Spring mail, config seam |
| nested event type inside a coupled class | move the type out |
| request-scoped `CurrentUser` | Spring request-scoped equivalent |
| `@SchedulerLock` interceptor | `shedlock-spring` (see `libs/shedlock.md`) |
| COPPER `CDIInjector` | `ApplicationContext.getBean(name)` injector (see `libs/copper-8.1.md`) |
| JAX-RS filters, auth mechanism, identity augmentor, `@RolesAllowed`, default-deny config | Spring Security filters, method security, default-deny chain (no twin for `deny-unannotated-endpoints`); keep exact semantics (disabled -> 401, lookup failure -> 503, DB roles override token groups) |
| second non-JTA datasource | separate `DataSource` bean outside the tx manager |
| CDI `SqlSessionFactory` | `mybatis-spring-boot` |
| Producers (`new XRepo(em)`) | `@Configuration` beans |

## Risks
- COPPER classpath scan: Spring Boot nested-jar fat jar hides workflows (0 found, silent). Use `PropertiesLauncher`/ZIP layout or explicit registration, and fail loudly on 0 workflows. Engine stays lazy; engine absent -> 503.
- `@Transactional` self-invocation differs between frameworks: spike it.
- Keep architecture-test rules (e.g. no `jakarta.persistence` in `*.boundary`) for the Spring controllers.
- Dependency versions: Copper runtime vs the Hibernate version Spring Boot manages: check the dependency tree first.

## Staging
1. Extract the shared module (needs the seams). 2. Spring skeleton: datasource, Flyway, repo config. 3. Auth/session. 4. Thin vertical slice. 5. Checkout/workflow outbox. 6. Admin screens. 7. Port integration tests last (`@SpringBootTest`, `TransactionTemplate`; REST Assured/Playwright port as-is).
