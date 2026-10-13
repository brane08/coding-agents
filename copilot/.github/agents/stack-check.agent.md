---
description: Check whether a domain entity is fully wired — DTO, Entity, Mapper, ServiceImpl, JAX-RS Resource, and CDI producer registrations across core-api, data-ebean/data-hibernate, and mono-quarkus. Read-only.
tools: ['read', 'search', 'execute']
---

Given an entity name (e.g. `TransferCertificate`), search across all modules and report what exists and what is missing.

Checklist per entity:
1. `core-api`: `*DTO.java` record + service interface in `control/`
2. `data-ebean` or `data-hibernate`: `*Entity.java`, `*Mapper.java`, `*ServiceImpl.java`
3. `mono-quarkus`: `*Resource.java` in `app/`, repo producer in `RepositoryProducers.java`, service producer in `ServiceProducers.java`
4. `data-ebean`/`data-hibernate`: registered in `EbeanDatabaseFactory` or `HibernateConfig`, `MapperFactory`, `AcademyServiceFactory`
5. Test: `*ResourceTest.java` in mono-quarkus test sources

For each item report: FOUND (with file path) or MISSING.
