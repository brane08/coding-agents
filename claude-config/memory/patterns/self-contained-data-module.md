# Pattern: Self-Contained Swappable Data Module

## Problem
In a layered architecture (core-api → data-X → app), repository and service CDI producers
often live in the app module. This means swapping the ORM (e.g. Ebean → Hibernate) requires
editing app-layer files that know every entity by name — defeating the point of a modular split.

## Solution
Move all CDI producers INTO the data module. The data module owns its own datasource bootstrap
and produces services directly. The app module declares a pom.xml dependency and nothing else.

## Structure

```
core-api/          DTOs (records), service interfaces, GenericRepository<E,ID> interface
                   — framework-neutral, no ORM dependency

data-ebean/        Ebean entities, mappers, service impls, EbeanGenericRepository
  EbeanProducers   ← self-bootstraps Database, produces all services as CDI beans

data-hibernate/    JPA entities (same package), mappers, service impls, HibernateGenericRepository
  HibernateProducers ← injects EntityManager, produces all services as CDI beans

app-module/        JAX-RS resources, workflows, REST wiring only
                   — zero knowledge of which data module is active
```

## Key Rule
**Repositories are never CDI beans.** They are created inline inside the producer method.
This eliminates @Named qualifier pollution and CDI ambiguity between generic types.

## Producer Pattern

### Ebean (self-bootstrapped)
```java
@ApplicationScoped
public class EbeanProducers {

    // Data module owns its own connection — no injection needed
    private final Database db = new EbeanDatabaseFactory().createDatabase();
    private final MapperFactory mappers = new MapperFactory();
    private final ServiceFactory services = new ServiceFactory(mappers);

    @Produces @ApplicationScoped
    public GradeService gradeService() {
        return services.gradeService(new EbeanGenericRepository<>(GradeEntity.class, db));
    }

    // Services that need raw Database pass it directly
    @Produces @ApplicationScoped
    public TimetableVersionService timetableVersionService() {
        return services.timetableVersionService(
            new EbeanGenericRepository<>(TimetableVersionEntity.class, db), db);
    }
}
```

### Hibernate (EntityManager injected by container)
```java
@ApplicationScoped
public class HibernateProducers {

    @PersistenceContext EntityManager em;  // container-managed
    private final MapperFactory mappers = new MapperFactory();
    private final ServiceFactory services = new ServiceFactory(mappers);

    @Produces @ApplicationScoped
    public GradeService gradeService() {
        return services.gradeService(new HibernateGenericRepository<>(GradeEntity.class, em));
    }
}
```

## Swapping ORM
1. In app `pom.xml`: remove `data-ebean`, add `data-hibernate`
2. Done. CDI discovers the new producers. No app-layer code changes.

## Migration Path (Ebean → Hibernate)
1. Port entities one domain at a time: copy to data-hibernate, swap Ebean annotations for JPA
2. Add service to HibernateProducers, remove from EbeanProducers
3. Once all entities ported, drop data-ebean from pom.xml

## Watch-outs
- During dual-ORM transition: two connection pools share one datasource — cap both pool sizes
- Services with raw Database (not GenericRepository) need ORM-specific impls in each module
  (e.g. AcademicYearServiceImpl using Database → HibernateAcademicYearServiceImpl using EntityManager)
- data-ebean needs jakarta.enterprise.inject + jakarta.inject deps added (CDI spec, not Quarkus-specific)
- data-hibernate naturally gets CDI via quarkus-hibernate-orm-panache

## Applicable When
- Multi-module Maven/Gradle monorepo
- Shared service/DTO layer (core-api) across ORM implementations
- Any Jakarta EE / Quarkus / Spring project needing ORM portability
- YAGNI check: only worth it if ORM swap is a real roadmap item, not speculative
